# Magento DEV Docker Stack

A complete **Magento development environment** powered by Docker.  
This repository provisions a full Magento stack suitable for local development or fresh VM environments.

## Stack Components

The stack includes the following services:

- **nginx** – web server
- **php-fpm** – PHP runtime
- **mariadb** – local development database
- **opensearch** – Magento search engine
- **redis** – cache and session storage
- **rabbitmq** – message queue
- **cron** – Magento scheduled tasks

All services start automatically using Docker Compose.

On first startup the PHP container automatically performs the Magento bootstrap process.

---

# Automatic Bootstrap Process

During the first container startup the following steps are executed automatically:

1. Magento source code is downloaded using Composer
2. Project dependencies are installed
3. The container waits until required services are available:
   - MariaDB
   - OpenSearch
   - Redis
   - RabbitMQ
4. Magento installation is executed:

```bash
bin/magento setup:install
```

5. A basic Magento warm-up process runs

After completion Magento becomes available at the configured base URL.

---

# Repository Structure

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
`-- data/         # optional; runtime state currently uses Docker named volumes
```

---

# Host Requirements

The following kernel parameter must be configured on the host system for OpenSearch.

```bash
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee /etc/sysctl.d/99-opensearch.conf
```

This setting is required before starting the containers.

---

# Environment Configuration

Create the environment configuration file:

```bash
cp .env.example .env
```

At minimum the following values must be configured:

| Variable                | Description                           |
| ----------------------- | ------------------------------------- |
| `MAGENTO_DB_PASSWORD`   | Magento database password             |
| `MARIADB_ROOT_PASSWORD` | MariaDB root password                 |
| `MAGENTO_BASE_URL`      | Base URL for the Magento installation |
| `MAGENTO_PUBLIC_KEY`    | Magento repository key                |
| `MAGENTO_PRIVATE_KEY`   | Magento repository secret             |

The Magento repository keys are required for installing patch releases from `repo.magento.com`.

---

# Starting the Environment

## Linux

```bash
./setup.sh
```

## Windows PowerShell

```powershell
.\setup.ps1
```

## Manual Start

```bash
docker compose up -d --build
```

---

# Monitoring the Bootstrap Process

The Magento installation progress can be followed through container logs.

```bash
docker compose logs -f php
```

Once the bootstrap process completes, Magento becomes accessible at the configured `MAGENTO_BASE_URL`.

---

# Database Configuration

The development environment runs a **local MariaDB instance** by default.

| Service | Internal Address | Host Port        |
| ------- | ---------------- | ---------------- |
| MariaDB | `db:3306`        | `localhost:3307` |

The database host can be changed in `.env` to use an external database:

```env
MAGENTO_DB_HOST=db-server.internal
```

---

# Important Notes

* Patch versions such as `2.4.8-p4` require Magento repository credentials (`repo.magento.com`)
* Versions without patch suffix can fallback to the public `magento/magento2` GitHub repository
* MariaDB, Redis, RabbitMQ, and OpenSearch use **Docker named volumes** to improve stability on Windows
* PHP-FPM runs as **root in development mode** to avoid bind mount permission issues during Magento code generation
* The stack defaults to:

  * **Magento 2.4.8-p4**
  * **PHP 8.3**
* Magento source code is stored in a **Docker named volume** by default instead of a bind mount

This design improves reliability during first-time installation on both Linux and Windows.

For development workflows that require direct source editing, a Compose override can be created to mount a local `src/` directory.

---

# Useful Commands

Check running containers:

```bash
docker compose ps
```

View service logs:

```bash
docker compose logs -f nginx
docker compose logs -f db
docker compose logs -f cron
```

Check Magento installation status:

```bash
docker compose exec php php bin/magento setup:status
```

Connect to the database:

```bash
docker compose exec db mariadb -uroot -p
```

Check Redis:

```bash
docker compose exec redis redis-cli ping
```

Check RabbitMQ:

```bash
docker compose exec rabbitmq rabbitmq-diagnostics ping
```

Check OpenSearch:

```bash
curl http://localhost:${HOST_OPENSEARCH_PORT:-9200}
```

