#!/bin/sh
set -eu

APP_DIR="${APP_DIR:-/var/www/html}"

log() {
  printf '[magento-cron] %s\n' "$1"
}

while [ ! -f "${APP_DIR}/app/etc/env.php" ]; do
  log "Wachten op app/etc/env.php"
  sleep 10
done

while true; do
  php "${APP_DIR}/bin/magento" cron:run || true
  sleep 60
done
