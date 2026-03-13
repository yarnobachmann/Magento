#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ENV_FILE="${ROOT_DIR}/.env"

cd "${ROOT_DIR}"

if [ ! -f "${ENV_FILE}" ]; then
  cp "${ROOT_DIR}/.env.example" "${ENV_FILE}"
  echo ".env aangemaakt vanuit .env.example"
fi

set -a
. "${ENV_FILE}"
set +a

if [ -z "${MAGENTO_BASE_URL:-}" ]; then
  echo "MAGENTO_BASE_URL ontbreekt in .env"
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker ontbreekt op de host."
  exit 1
fi

if docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD="docker-compose"
else
  echo "Geen docker compose client gevonden."
  exit 1
fi

CURRENT_MAX_MAP_COUNT=$(sysctl -n vm.max_map_count 2>/dev/null || echo "")
if [ "${CURRENT_MAX_MAP_COUNT}" != "262144" ]; then
  echo "Waarschuwing: vm.max_map_count is ${CURRENT_MAX_MAP_COUNT:-onbekend}, aanbevolen is 262144 voor OpenSearch."
  echo "Zet dit op de host met: sudo sysctl -w vm.max_map_count=262144"
fi

echo "Compose config valideren"
$COMPOSE_CMD --env-file "${ENV_FILE}" config >/dev/null || {
  echo "Compose configuratie is ongeldig."
  exit 1
}

echo "Stack builden en starten"
$COMPOSE_CMD --env-file "${ENV_FILE}" up -d --build

echo "Wachten tot php container beschikbaar is"
PHP_CONTAINER=$($COMPOSE_CMD --env-file "${ENV_FILE}" ps -q php)

if [ -z "${PHP_CONTAINER}" ]; then
  echo "PHP container niet gevonden."
  exit 1
fi

ATTEMPTS=0
until docker exec "${PHP_CONTAINER}" sh -c 'php -v >/dev/null 2>&1'; do
  ATTEMPTS=$((ATTEMPTS + 1))
  if [ "${ATTEMPTS}" -ge 60 ]; then
    echo "PHP container is niet tijdig beschikbaar."
    exit 1
  fi
  sleep 2
done

echo "Wachten tot Magento CLI beschikbaar is"
ATTEMPTS=0
until docker exec "${PHP_CONTAINER}" sh -c '[ -f /var/www/html/bin/magento ]'; do
  ATTEMPTS=$((ATTEMPTS + 1))
  if [ "${ATTEMPTS}" -ge 60 ]; then
    echo "Magento CLI niet gevonden in /var/www/html/bin/magento"
    exit 1
  fi
  sleep 2
done

echo "Controleren op maintenance flag"
if docker exec "${PHP_CONTAINER}" sh -c '[ -f /var/www/html/var/.maintenance.flag ]'; then
  echo "Maintenance flag gevonden, verwijderen"
  docker exec "${PHP_CONTAINER}" rm -f /var/www/html/var/.maintenance.flag
else
  echo "Geen maintenance flag gevonden"
fi

echo "Magento maintenance mode uitschakelen"
docker exec "${PHP_CONTAINER}" sh -c 'cd /var/www/html && php bin/magento maintenance:disable || true'

echo "Magento base URL forceren"
docker exec "${PHP_CONTAINER}" sh -c "cd /var/www/html && php bin/magento config:set web/unsecure/base_url '${MAGENTO_BASE_URL}'"
docker exec "${PHP_CONTAINER}" sh -c "cd /var/www/html && php bin/magento config:set web/secure/base_url '${MAGENTO_BASE_URL}'"
docker exec "${PHP_CONTAINER}" sh -c 'cd /var/www/html && php bin/magento config:set web/secure/use_in_frontend 0 || true'
docker exec "${PHP_CONTAINER}" sh -c 'cd /var/www/html && php bin/magento config:set web/secure/use_in_adminhtml 0 || true'

echo "Magento setup:upgrade uitvoeren"
docker exec "${PHP_CONTAINER}" sh -c 'cd /var/www/html && php bin/magento setup:upgrade'

echo "Magento deploy mode op developer zetten"
docker exec "${PHP_CONTAINER}" sh -c 'cd /var/www/html && php bin/magento deploy:mode:set developer || true'

echo "Generated code en caches opruimen"
docker exec "${PHP_CONTAINER}" sh -c 'cd /var/www/html && rm -rf generated/code/* generated/metadata/* var/cache/* var/page_cache/* var/view_preprocessed/* pub/static/frontend/* pub/static/adminhtml/* || true'

echo "DI compile uitvoeren"
docker exec "${PHP_CONTAINER}" sh -c 'cd /var/www/html && php bin/magento setup:di:compile'

echo "Static content deploy uitvoeren"
docker exec "${PHP_CONTAINER}" sh -c 'cd /var/www/html && php bin/magento setup:static-content:deploy -f en_US nl_NL || true'

echo "Cache flush uitvoeren"
docker exec "${PHP_CONTAINER}" sh -c 'cd /var/www/html && php bin/magento cache:flush || true'

echo "Indexers draaien"
docker exec "${PHP_CONTAINER}" sh -c 'cd /var/www/html && php bin/magento indexer:reindex || true'

echo "Magento maintenance mode nogmaals uitschakelen"
docker exec "${PHP_CONTAINER}" sh -c 'cd /var/www/html && php bin/magento maintenance:disable || true'
docker exec "${PHP_CONTAINER}" sh -c 'rm -f /var/www/html/var/.maintenance.flag || true'

echo "PHP en nginx herstarten"
$COMPOSE_CMD --env-file "${ENV_FILE}" restart php nginx || true

echo "Huidige containerstatus"
$COMPOSE_CMD --env-file "${ENV_FILE}" ps

echo "Huidige Magento base URL"
docker exec "${PHP_CONTAINER}" sh -c 'cd /var/www/html && php bin/magento config:show web/unsecure/base_url || true'

echo "Setup voltooid"
echo "Controleer de site via ${MAGENTO_BASE_URL}"
echo "Gebruik '$COMPOSE_CMD --env-file \"${ENV_FILE}\" logs -f php' voor troubleshooting."