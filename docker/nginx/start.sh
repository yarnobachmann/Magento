#!/bin/sh
set -eu

APP_DIR="/var/www/html"

while [ ! -f "${APP_DIR}/app/etc/env.php" ]; do
  sleep 5
done

exec nginx -g 'daemon off;'
