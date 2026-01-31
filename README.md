# Self-Hosted Appwrite Docker Setup

This repository contains a containerized setup for self-hosting Appwrite using Docker. It includes automated configuration scripts, secure secret generation, and persistent data management using Docker volumes.

## Prerequisites

- **Docker**: Engine version 24.0+ is recommended.
- **Docker Compose**: Plugin version v2.0+.
- **Git**: To clone this repository.
- **OpenSSL**: Used for secret generation (usually pre-installed on Linux/macOS).
- **Python 3**: Used for generating pronounceable database passwords.

## Quick Start

1.  **Run the Setup Script**
    This script automates the creation of the `.env` file, generates secure random secrets (encryption keys, executor secrets, database passwords), and configures initial credentials.

    ```bash
    ./setup.sh
    ```

    *The script will copy `.env.example` to `.env` and fill in the necessary values. It also handles setting up file permissions.*

2.  **Start Services**
    Launch the Appwrite stack in detached mode:

    ```bash
    docker compose up -d
    ```

3.  **Monitor Startup**
    Verify that all services are healthy. The database (`mariadb`) may take a moment to initialize on the first run.

    ```bash
    docker compose ps
    ```

    You can check the logs if something seems wrong:

    ```bash
    docker compose logs -f appwrite
    ```

## Accessing Services

Once all containers are running and healthy, you can access the services on your local network/host:

| Service | URL | Default Credential (User/Pass) | Description |
| :--- | :--- | :--- | :--- |
| **Appwrite Console** | `http://localhost:8080` | *(Create Account)* | The main dashboard for managing your Appwrite project. Port is mapped to `_APP_MAIN_PORT_HTTP` in `.env`. |
| **API Endpoint** | `http://localhost:8080/v1` | N/A | Entry point for Appwrite APIs. |
| **MariaDB Database** | `localhost:3306` | *(See .env)* | Direct database access. User: `_APP_DB_USER`, Pass: `_APP_DB_PASS`. Port is mapped to `_APP_DB_PORT`. |
| **Redis** | `localhost:6379` | N/A | Cache and message broker. Port is mapped to `_APP_REDIS_PORT`. |

> **Note**: Your specific passwords (like `_APP_DB_PASS` and `_APP_DB_ROOT_PASS`) are generated randomly and stored in your `.env` file. Check that file to retrieve them.

## Configuration (.env)

The `.env` file is the single source of truth for your configuration.

-   **Ports**: You can customize ports (`_APP_MAIN_PORT_HTTP`, `_APP_DB_PORT`, etc.) directly in `.env`.
-   **Environment**: Change `_APP_ENV` to `production` for production deployments.
-   **Domain**: Update `_APP_DOMAIN` if accessing from a public domain or different IP.
-   **SMTP**: Configure the SMTP section in `.env` to enable email delivery.

## Stopping Services

To stop the containers but **preserve your data**:

```bash
docker compose stop
```

To stop and remove containers (data in volumes is still preserved):

```bash
docker compose down
```

## Complete Teardown & Data Removal

**WARNING: This will delete ALL your database data, users, and uploaded files. This action is irreversible.**

To completely remove the deployment and all associated data volumes:

1.  **Stop and remove containers + volumes**:
    ```bash
    docker compose down -v
    ```

2.  **Remove local persistent data**:
    If you want to start completely fresh (deleting all database data, uploaded files, cache, and generated keys), remove the locally mounted Docker volumes.
    *Note: This requires sudo because many of these files are owned by root or container users.*

    ```bash
    # Remove all named volumes managed by Docker
    docker volume rm $(docker volume ls -q --filter name=appwrite)
    ```

3.  **Reset Configuration**:
    To generate fresh passwords and secrets on the next run:
    ```bash
    rm .env
    ```

Copyright © 2026 ryumada. All Rights Reserved.

Licensed under the [MIT](LICENSE) license.
