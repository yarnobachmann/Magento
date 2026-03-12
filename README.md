# Magento DEV Docker repo

Deze repo zet een complete Magento DEV stack op voor `mag-dev`, passend bij je serverlog:

- `nginx`
- `php-fpm`
- `mariadb` (tijdelijk lokaal voor testgebruik)
- `opensearch`
- `redis`
- `rabbitmq`
- `cron`
- optioneel externe MariaDB door `MAGENTO_DB_HOST` in `.env` te wijzigen

De stack is zo opgezet dat `docker compose up -d` alles start. De `php` container bootstrapt op de eerste run automatisch:

1. Magento broncode downloaden via Composer
2. dependencies installeren
3. wachten op DB, OpenSearch, Redis en RabbitMQ
4. `bin/magento setup:install` uitvoeren
5. basis warm-up draaien

## Structuur

```text
.
|-- compose.yaml
|-- .env.example
|-- docker/
|   |-- nginx/default.conf
|   `-- php/
|       |-- Dockerfile
|       |-- php.ini
|       |-- entrypoint.sh
|       `-- cron.sh
|-- setup.sh
|-- setup.ps1
`-- data/         # optioneel; runtime state gebruikt nu Docker named volumes
```

## Voorwaarden op de host

Deze twee hoststappen blijven nodig buiten Docker:

```bash
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee /etc/sysctl.d/99-opensearch.conf
```

Als je later weer je centrale DB wilt gebruiken, zet dan `MAGENTO_DB_HOST=db-server.internal` in `.env`.

## Gebruik

1. Maak je `.env`:

```bash
cp .env.example .env
```

2. Vul minimaal deze velden in:

- `MAGENTO_DB_PASSWORD`
- `MARIADB_ROOT_PASSWORD`
- eventueel `MAGENTO_BASE_URL` als je niet `http://localhost/` wilt gebruiken
- optioneel `MAGENTO_PUBLIC_KEY` en `MAGENTO_PRIVATE_KEY` voor download via `repo.magento.com`

3. Start de stack:

Linux:

```bash
./setup.sh
```

Windows PowerShell:

```powershell
.\setup.ps1
```

Handmatig kan ook nog steeds:

```bash
docker compose up -d --build
```

4. Volg de eerste bootstrap:

```bash
docker compose logs -f php
```

Als de bootstrap klaar is, hoort Magento bereikbaar te zijn op `MAGENTO_BASE_URL`.

## Belangrijke notities

- Patch releases zoals `2.4.8-p4` vereisen `MAGENTO_PUBLIC_KEY` en `MAGENTO_PRIVATE_KEY`, omdat die via `repo.magento.com` komen.
- Alleen zonder patchsuffix kan de bootstrap terugvallen op de publieke `magento/magento2` GitHub-tag.
- De lokale testdatabase draait standaard op `db:3306` binnen Docker en wordt naar de host gepubliceerd op `localhost:3307`.
- MariaDB, Redis, RabbitMQ en OpenSearch gebruiken Docker named volumes in plaats van Windows bind mounts, omdat dat op Windows veel betrouwbaarder is voor Magento.
- Op Windows draait PHP-FPM in deze DEV-stack bewust als `root` om bind mount permissieproblemen met Magento codegeneratie te vermijden.
- De repo staat nu standaard op `Magento 2.4.8-p4` en `PHP 8.3`.
- Magento code draait standaard vanuit een Docker named volume in plaats van een host bind mount. Dat is op Linux en Windows betrouwbaarder voor de eerste installatie.
- Als je later toch met een lokale `src/` map wilt ontwikkelen, kun je daar een aparte compose override voor maken, maar voor een verse VM is de default-opzet expres volledig self-contained.
- `docker compose up -d` kan op een eerste Windows run nog steeds lang duren door `composer install`, maar de stack abort niet meer voortijdig op de PHP healthcheck; `nginx` wacht nu zelf tot Magento klaar is.

## Handige checks

```bash
docker compose ps
docker compose logs -f nginx
docker compose logs -f db
docker compose logs -f cron
docker compose exec php php bin/magento setup:status
docker compose exec db mariadb -uroot -p
docker compose exec redis redis-cli ping
docker compose exec rabbitmq rabbitmq-diagnostics ping
curl http://localhost:${HOST_OPENSEARCH_PORT:-9200}
```
