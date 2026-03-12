#!/bin/sh
set -eu

APP_DIR="${APP_DIR:-/var/www/html}"
COMPOSER_HOME="${COMPOSER_HOME:-/tmp/composer}"

log() {
  printf '[magento-entrypoint] %s\n' "$1"
}

ensure_composer_auth() {
  if [ -n "${MAGENTO_PUBLIC_KEY:-}" ] && [ -n "${MAGENTO_PRIVATE_KEY:-}" ]; then
    mkdir -p "${COMPOSER_HOME}"
    cat > "${COMPOSER_HOME}/auth.json" <<EOF
{
  "http-basic": {
    "repo.magento.com": {
      "username": "${MAGENTO_PUBLIC_KEY}",
      "password": "${MAGENTO_PRIVATE_KEY}"
    }
  }
}
EOF
  fi
}

write_runtime_php_ini() {
  cat > /usr/local/etc/php/conf.d/zz-runtime.ini <<EOF
memory_limit = ${PHP_MEMORY_LIMIT:-2G}
max_execution_time = ${PHP_MAX_EXECUTION_TIME:-1800}
max_input_time = 1800
upload_max_filesize = ${PHP_UPLOAD_MAX_FILESIZE:-64M}
post_max_size = ${PHP_POST_MAX_SIZE:-64M}
date.timezone = ${TZ:-Europe/Amsterdam}
EOF
}

wait_for_tcp() {
  host="$1"
  port="$2"
  name="$3"

  i=0
  until nc -z "${host}" "${port}" >/dev/null 2>&1; do
    i=$((i + 1))
    if [ "${i}" -ge 120 ]; then
      log "${name} is niet bereikbaar op ${host}:${port}"
      exit 1
    fi
    sleep 2
  done
}

wait_for_http() {
  url="$1"
  name="$2"

  i=0
  until curl -fsS "${url}" >/dev/null 2>&1; do
    i=$((i + 1))
    if [ "${i}" -ge 120 ]; then
      log "${name} geeft geen gezonde HTTP response op ${url}"
      exit 1
    fi
    sleep 2
  done
}

bootstrap_codebase() {
  if [ -f "${APP_DIR}/composer.json" ]; then
    return
  fi

  mkdir -p "${APP_DIR}"
  if [ -n "$(find "${APP_DIR}" -mindepth 1 -maxdepth 1 2>/dev/null)" ]; then
    log "${APP_DIR} is niet leeg, maar bevat geen Magento composer.json."
    exit 1
  fi

  if [ -n "${MAGENTO_PUBLIC_KEY:-}" ] && [ -n "${MAGENTO_PRIVATE_KEY:-}" ]; then
    package="magento/project-community-edition"
    if [ "${MAGENTO_EDITION:-community}" = "enterprise" ]; then
      package="magento/project-enterprise-edition"
    fi

    log "Download Magento ${MAGENTO_VERSION:-2.4.8} via Composer"
    composer create-project \
      --repository-url=https://repo.magento.com/ \
      --no-interaction \
      "${package}=${MAGENTO_VERSION:-2.4.8}" \
      "${APP_DIR}"
    return
  fi

  case "${MAGENTO_VERSION:-}" in
    *-p*)
      log "Magento ${MAGENTO_VERSION} vereist download via repo.magento.com."
      log "Vul MAGENTO_PUBLIC_KEY en MAGENTO_PRIVATE_KEY in om patch releases zoals -p4 te installeren."
      exit 1
      ;;
  esac

  log "Composer keys ontbreken, fallback naar publieke GitHub broncode"
  git clone --branch "${MAGENTO_VERSION:-2.4.8}" --depth 1 https://github.com/magento/magento2.git "${APP_DIR}"
}

install_dependencies() {
  if [ -f "${APP_DIR}/vendor/autoload.php" ]; then
    return
  fi

  log "Composer dependencies installeren"
  composer install --working-dir="${APP_DIR}" --no-interaction
}

set_permissions() {
  mkdir -p "${APP_DIR}/var" "${APP_DIR}/generated" "${APP_DIR}/pub/static" "${APP_DIR}/pub/media" "${APP_DIR}/app/etc"
  chown -R www-data:www-data "${APP_DIR}"
  find "${APP_DIR}/var" "${APP_DIR}/generated" "${APP_DIR}/pub/static" "${APP_DIR}/pub/media" "${APP_DIR}/app/etc" -type d -exec chmod 775 {} +
  find "${APP_DIR}/var" "${APP_DIR}/generated" "${APP_DIR}/pub/static" "${APP_DIR}/pub/media" "${APP_DIR}/app/etc" -type f -exec chmod 664 {} + || true
  chmod +x "${APP_DIR}/bin/magento" || true
}

wait_for_dependencies() {
  wait_for_tcp "${MAGENTO_DB_HOST}" "${MAGENTO_DB_PORT:-3306}" "database"
  wait_for_http "http://${MAGENTO_OPENSEARCH_HOST}:${MAGENTO_OPENSEARCH_PORT:-9200}" "opensearch"
  wait_for_tcp "${MAGENTO_REDIS_HOST}" "${MAGENTO_REDIS_PORT:-6379}" "redis"
  wait_for_tcp "${MAGENTO_RABBITMQ_HOST}" "${MAGENTO_RABBITMQ_PORT:-5672}" "rabbitmq"
}

install_magento() {
  if [ -f "${APP_DIR}/app/etc/env.php" ]; then
    return
  fi

  frontname_arg=""
  if [ -n "${MAGENTO_BACKEND_FRONTNAME:-}" ]; then
    frontname_arg="--backend-frontname=${MAGENTO_BACKEND_FRONTNAME}"
  fi

  log "Magento setup:install uitvoeren"
  php "${APP_DIR}/bin/magento" setup:install \
    --base-url="${MAGENTO_BASE_URL}" \
    --db-host="${MAGENTO_DB_HOST}" \
    --db-name="${MAGENTO_DB_NAME}" \
    --db-user="${MAGENTO_DB_USER}" \
    --db-password="${MAGENTO_DB_PASSWORD}" \
    --admin-firstname="${MAGENTO_ADMIN_FIRSTNAME}" \
    --admin-lastname="${MAGENTO_ADMIN_LASTNAME}" \
    --admin-email="${MAGENTO_ADMIN_EMAIL}" \
    --admin-user="${MAGENTO_ADMIN_USER}" \
    --admin-password="${MAGENTO_ADMIN_PASSWORD}" \
    --language="${MAGENTO_LANGUAGE}" \
    --currency="${MAGENTO_CURRENCY}" \
    --timezone="${MAGENTO_TIMEZONE}" \
    --use-rewrites="${MAGENTO_USE_REWRITES:-1}" \
    --search-engine="opensearch" \
    --opensearch-host="${MAGENTO_OPENSEARCH_HOST}" \
    --opensearch-port="${MAGENTO_OPENSEARCH_PORT:-9200}" \
    --opensearch-index-prefix="${MAGENTO_OPENSEARCH_INDEX_PREFIX:-magento2}" \
    --opensearch-timeout="${MAGENTO_OPENSEARCH_TIMEOUT:-15}" \
    --cache-backend="redis" \
    --cache-backend-redis-server="${MAGENTO_REDIS_HOST}" \
    --cache-backend-redis-port="${MAGENTO_REDIS_PORT:-6379}" \
    --page-cache="redis" \
    --page-cache-redis-server="${MAGENTO_REDIS_HOST}" \
    --page-cache-redis-port="${MAGENTO_REDIS_PORT:-6379}" \
    --session-save="redis" \
    --session-save-redis-host="${MAGENTO_REDIS_HOST}" \
    --session-save-redis-port="${MAGENTO_REDIS_PORT:-6379}" \
    --amqp-host="${MAGENTO_RABBITMQ_HOST}" \
    --amqp-port="${MAGENTO_RABBITMQ_PORT:-5672}" \
    --amqp-user="${MAGENTO_RABBITMQ_USER}" \
    --amqp-password="${MAGENTO_RABBITMQ_PASSWORD}" \
    --amqp-virtualhost="${MAGENTO_RABBITMQ_VHOST:-/}" \
    ${frontname_arg}
}

warmup_magento() {
  if [ ! -f "${APP_DIR}/app/etc/env.php" ]; then
    return
  fi

  locales="${MAGENTO_STATIC_CONTENT_LOCALES:-${MAGENTO_LANGUAGE:-en_US}}"
  case " ${locales} " in
    *" en_US "*) ;;
    *) locales="${locales} en_US" ;;
  esac

  log "Magento warm-up taken uitvoeren"
  php "${APP_DIR}/bin/magento" setup:upgrade --keep-generated || true
  php "${APP_DIR}/bin/magento" module:disable Magento_TwoFactorAuth Magento_AdminAdobeImsTwoFactorAuth || true
  php "${APP_DIR}/bin/magento" setup:static-content:deploy -f ${locales} || true
  php "${APP_DIR}/bin/magento" indexer:reindex || true
  php "${APP_DIR}/bin/magento" cache:flush || true
}

main() {
  mkdir -p "${COMPOSER_HOME}"
  write_runtime_php_ini
  ensure_composer_auth
  bootstrap_codebase
  install_dependencies
  set_permissions
  wait_for_dependencies
  install_magento
  set_permissions
  warmup_magento
  exec "$@"
}

main "$@"
