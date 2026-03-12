#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ENV_FILE="${ROOT_DIR}/.env"

if [ ! -f "${ENV_FILE}" ]; then
  cp "${ROOT_DIR}/.env.example" "${ENV_FILE}"
  echo ".env aangemaakt vanuit .env.example"
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
fi

echo "Compose config valideren"
$COMPOSE_CMD config >/dev/null

echo "Stack builden en starten"
$COMPOSE_CMD up -d --build

echo "Gebruik '$COMPOSE_CMD logs -f php' om de eerste Magento bootstrap te volgen."
