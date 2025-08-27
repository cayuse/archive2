# Archive Deployment Guide

## Environment Setup (Exports)

**IMPORTANT**: You must set these environment variables before running any deployment commands. Each deployment type requires different variables.

### 1) Base Exports (Required for ALL deployments)

These variables are needed regardless of whether you're deploying a master, slave, or standalone system:

```bash
# Rails encryption key - REQUIRED for all deployments
export RAILS_MASTER_KEY=your_rails_master_key_here

# PostgreSQL database password - REQUIRED for all deployments
export POSTGRES_PASSWORD=your_secure_password_here

# Host storage paths - REQUIRED for all deployments
export HOST_STORAGE_PATH=/path/to/your/postgresql/storage/directory
export POSTGRES_DATA_PATH=/path/to/your/postgresql/data/directory

# Application port - REQUIRED for all deployments
export ARCHIVE_PORT=3000
```

### 2) Choose ONE Role Overlay

**Only ONE of these sections should be used per deployment.**

#### Overlay: Standalone Archive (Single server, no replication)

```bash
# Role identifier
export ARCHIVE_ROLE=standalone

# Application configuration
export APP_HOST=your_server_ip_or_hostname
export APP_PROTOCOL=http  # or https if using SSL
export FORCE_SSL=false    # set to true if using SSL
export ASSUME_SSL=false   # set to true if behind reverse proxy with SSL
export FORGERY_ORIGIN_CHECK=false  # disable strict CSRF for testing
export ALLOW_ALL_HOSTS=true        # accept any Host header during testing

# Docker Compose files (base only)
export COMPOSE_FILE="docker-compose.yml"
```

#### Overlay: Master (Production with reverse proxy, no replication)

```bash
# Role identifier
export ARCHIVE_ROLE=master

# Application configuration
export APP_HOST=your_public_domain_or_ip
export APP_PROTOCOL=https  # typically https in production
export FORCE_SSL=true      # enforce SSL
export ASSUME_SSL=true     # assume SSL from reverse proxy
export FORGERY_ORIGIN_CHECK=true   # enable CSRF protection
export ALLOW_ALL_HOSTS=false       # restrict to specific hosts

# Docker Compose files (base only)
export COMPOSE_FILE="docker-compose.yml"
```

#### Overlay: Slave (Replication target - connects to master)

```bash
# Role identifier
export ARCHIVE_ROLE=slave

# Application configuration (this slave's address)
export APP_HOST=this_slave_server_ip_or_hostname
export APP_PROTOCOL=http  # typically http for internal slaves
export FORCE_SSL=false    # slaves usually don't need SSL
export ASSUME_SSL=false   # no reverse proxy SSL
export FORGERY_ORIGIN_CHECK=false  # disable for internal testing
export ALLOW_ALL_HOSTS=true        # accept any Host header during testing

# Docker Compose files (base + replication overlay)
export COMPOSE_FILE="docker-compose.yml:docker-compose.replication.yml"

# Bucardo local database connection (this slave's database)
export BUCARDO_LOCAL_DB_HOST=db                    # Docker service name
export BUCARDO_LOCAL_DB_PORT=5432                  # PostgreSQL port
export BUCARDO_LOCAL_DB_NAME=bucardo               # Bucardo database name
export BUCARDO_LOCAL_DB_USER=bucardo               # Bucardo database user
export BUCARDO_LOCAL_DB_PASS=bucardo               # Bucardo database password

# Master database connection (reachable from this slave via VPN/LAN)
export MASTER_DB_HOST=192.168.1.201                # Master server IP
export MASTER_DB_PORT=5432                         # Master PostgreSQL port
export MASTER_DB_NAME=archive_production           # Master database name
export MASTER_DB_USER=postgres                     # Master database user
export MASTER_DB_PASS=$POSTGRES_PASSWORD           # Master database password

# Bucardo master database connection (convenience variables)
export BUCARDO_MASTER_DB_HOST=$MASTER_DB_HOST      # Same as MASTER_DB_HOST
export BUCARDO_MASTER_DB_PORT=$MASTER_DB_PORT      # Same as MASTER_DB_PORT
export BUCARDO_MASTER_DB_NAME=$MASTER_DB_NAME      # Same as MASTER_DB_NAME
export BUCARDO_MASTER_DB_USER=$MASTER_DB_USER      # Same as MASTER_DB_USER
export BUCARDO_MASTER_DB_PASS=$MASTER_DB_PASS      # Same as MASTER_DB_PASS

# Bucardo sync direction
export BUCARDO_SYNC_DIRECTION=slave_from_master    # This slave pulls from master
```

### 3) Variable Reference Guide

#### Required Variables (All Deployments)
- **`RAILS_MASTER_KEY`**: Rails encryption key for secure cookies and sessions
- **`POSTGRES_PASSWORD`**: Password for PostgreSQL database
- **`HOST_STORAGE_PATH`**: Host directory for PostgreSQL storage files
- **`POSTGRES_DATA_PATH`**: Host directory for PostgreSQL data files
- **`ARCHIVE_PORT`**: Host port that maps to container port 3000

#### Role-Specific Variables
- **`ARCHIVE_ROLE`**: Must be `standalone`, `master`, or `slave`
- **`COMPOSE_FILE`**: Docker Compose files to use (base + overlays)

#### Application Configuration Variables
- **`APP_HOST`**: IP address or hostname where the application will be accessible
- **`APP_PROTOCOL`**: `http` or `https`
- **`FORCE_SSL`**: Whether to enforce SSL connections
- **`ASSUME_SSL`**: Whether to assume SSL from reverse proxy
- **`FORGERY_ORIGIN_CHECK`**: Enable/disable CSRF protection
- **`ALLOW_ALL_HOSTS`**: Whether to accept any Host header

#### Slave-Only Variables (Replication)
- **`BUCARDO_LOCAL_DB_*`**: Connection details for this slave's local database
- **`MASTER_DB_*`**: Connection details for the master database
- **`BUCARDO_MASTER_DB_*`**: Same as MASTER_DB_* (convenience for Bucardo)
- **`BUCARDO_SYNC_DIRECTION`**: How this slave syncs with master

### 4) Quick Setup Examples

#### For a Standalone Server:
```bash
export RAILS_MASTER_KEY=your_key
export POSTGRES_PASSWORD=your_password
export HOST_STORAGE_PATH=/home/shared/psql_storage
export POSTGRES_DATA_PATH=/home/shared/psql_data
export ARCHIVE_PORT=3000
export ARCHIVE_ROLE=standalone
export APP_HOST=192.168.1.100
export APP_PROTOCOL=http
export FORCE_SSL=false
export ASSUME_SSL=false
export FORGERY_ORIGIN_CHECK=false
export ALLOW_ALL_HOSTS=true
export COMPOSE_FILE="docker-compose.yml"
```

#### For a Master Server:
```bash
export RAILS_MASTER_KEY=your_key
export POSTGRES_PASSWORD=your_password
export HOST_STORAGE_PATH=/home/shared/psql_storage
export POSTGRES_DATA_PATH=/home/shared/psql_data
export ARCHIVE_PORT=3000
export ARCHIVE_ROLE=master
export APP_HOST=yourdomain.com
export APP_PROTOCOL=https
export FORCE_SSL=true
export ASSUME_SSL=true
export FORGERY_ORIGIN_CHECK=true
export ALLOW_ALL_HOSTS=false
export COMPOSE_FILE="docker-compose.yml"
```

#### For a Slave Server:
```bash
export RAILS_MASTER_KEY=your_key
export POSTGRES_PASSWORD=your_password
export HOST_STORAGE_PATH=/home/shared/psql_storage
export POSTGRES_DATA_PATH=/home/shared/psql_data
export ARCHIVE_PORT=3000
export ARCHIVE_ROLE=slave
export APP_HOST=192.168.1.161
export APP_PROTOCOL=http
export FORCE_SSL=false
export ASSUME_SSL=false
export FORGERY_ORIGIN_CHECK=false
export ALLOW_ALL_HOSTS=true
export COMPOSE_FILE="docker-compose.yml:docker-compose.replication.yml"
export BUCARDO_LOCAL_DB_HOST=db
export BUCARDO_LOCAL_DB_PORT=5432
export BUCARDO_LOCAL_DB_NAME=bucardo
export BUCARDO_LOCAL_DB_USER=bucardo
export BUCARDO_LOCAL_DB_PASS=bucardo
export MASTER_DB_HOST=192.168.1.201
export MASTER_DB_PORT=5432
export MASTER_DB_NAME=archive_production
export MASTER_DB_USER=postgres
export MASTER_DB_PASS=$POSTGRES_PASSWORD
export BUCARDO_MASTER_DB_HOST=$MASTER_DB_HOST
export BUCARDO_MASTER_DB_PORT=$MASTER_DB_PORT
export BUCARDO_MASTER_DB_NAME=$MASTER_DB_NAME
export BUCARDO_MASTER_DB_USER=$MASTER_DB_USER
export BUCARDO_MASTER_DB_PASS=$MASTER_DB_PASS
export BUCARDO_SYNC_DIRECTION=slave_from_master
```

**IMPORTANT**: After setting your environment variables, verify them with `env | grep -E "(ARCHIVE|POSTGRES|APP_|BUCARDO|MASTER)"` before running deployment commands.

## Deployment Commands

### For Standalone or Master (No Replication)

```bash
cd archive
docker compose up -d --build
```

### For Slave (With Replication)

```bash
cd archive
bash deploy_slave.sh
```

## Bucardo Replication (Archive Master → Slave)

### Overview

- We use Syncthing for files and Bucardo for PostgreSQL replication.
- Bucardo runs only on the slave. The master is a normal Archive deployment.
- Replication direction for the first phase: master (source) → slave (target).
- Network access is via VPN (WireGuard recommended). Do not expose PostgreSQL to the public Internet.

### Master Deployment (First Principles)

On the master, deploy Archive normally (no Bucardo container):
```bash
cd ~/archive2/archive
docker compose -f docker-compose.yml up -d --build
```

Validate:
- App: http://<master_ip>:3000/up → green page
- DB: `docker compose logs db | tail`

Networking (VPN/WireGuard):
- Ensure the slave can reach `MASTER_DB_HOST:5432` over the VPN.
- On master Postgres, allow the VPN subnet in `pg_hba.conf` (the container uses the standard image; bind rules are managed via environment or by mounting a custom config if needed). Minimal example for a WireGuard /24:
```
host all all 10.8.0.0/24 scram-sha-256
```

### Slave Deployment (End-to-End)

On each slave, deploy Archive plus the Bucardo container:
```bash
cd ~/archive2/archive
docker compose -f docker-compose.yml -f docker-compose.replication.yml up -d --build

# Then run the slave deployment script to prep DBs and schema (optional but recommended)
bash deploy_slave.sh
```

What this does:
- Builds and starts PostgreSQL with Perl extensions (plperl/plperlu) and Archive app
- Creates the `bucardo` role/database
- Installs Bucardo schema into the `bucardo` database
- Builds and starts the `bucardo` container, which writes a minimal `~/.bucardorc` and starts the daemon

Verify containers:
```bash
docker ps
docker compose logs bucardo | tail -50
```

### Bucardo Post-Deploy Configuration (Slave)

Run these commands on the slave to register databases and set up the sync. The master must be reachable from the slave at `$MASTER_DB_HOST:$MASTER_DB_PORT`.

1) Inspect current state
```bash
docker compose exec bucardo bucardo status | cat
docker compose exec bucardo bucardo list dbs | cat
docker compose exec bucardo bucardo list relgroups | cat
docker compose exec bucardo bucardo list syncs | cat
```

2) Register databases with Bucardo
```bash
# Local (the archive_production DB inside this docker-compose)
docker compose exec bucardo \
  bucardo add database local \
  dbname=archive_production host=db port=5432 \
  user=postgres pass=$POSTGRES_PASSWORD | cat

# Master (remote master DB over VPN)
docker compose exec bucardo \
  bucardo add database master \
  dbname=$MASTER_DB_NAME host=$MASTER_DB_HOST port=$MASTER_DB_PORT \
  user=$MASTER_DB_USER pass=$MASTER_DB_PASS | cat
```

3) Add tables into a relgroup from the local DB
```bash
docker compose exec bucardo bucardo add all tables relgroup=rg_archive db=local | cat
```

4) Create the sync (one-time copy from master to local, then keep replicating)
```bash
docker compose exec bucardo \
  bucardo add sync archive_sync relgroup=rg_archive \
  dbs=master:source,local:target onetimecopy=2 | cat
```

5) Start and verify
```bash
docker compose exec bucardo bucardo start | cat
docker compose exec bucardo bucardo status | cat
docker compose exec bucardo bucardo list syncs | cat
docker compose logs -f bucardo
```

### Operational Notes

- The Bucardo container keeps running by tailing `/var/log/bucardo/bucardo.log`.
- Its startup script writes a minimal `~/.bucardorc` under `/var/lib/bucardo` and starts `bucardo` as the unprivileged `bucardo` user.
- The slave deploy script installs the Bucardo schema once; the container does not re-install it.

### Troubleshooting Bucardo

- Container restarts immediately:
  - `docker compose logs bucardo | tail -100`
  - Ensure you rebuilt with `docker compose build bucardo --no-cache`
- Bucardo connects to `localhost` instead of `db`:
  - Confirm `/var/lib/bucardo/.bucardorc` shows `dbhost=db`
- Auth failures to master:
  - Verify VPN routing and `pg_hba.conf` on master allows the slave's VPN IP
  - Check `$MASTER_DB_USER/$MASTER_DB_PASS` and DB name
- Verify DBs and syncs:
  - `docker compose exec bucardo bucardo list dbs | cat`
  - `docker compose exec bucardo bucardo status | cat`

### Security

- Use WireGuard VPN between master and slaves; do not expose PostgreSQL publicly.
- Constrain `pg_hba.conf` on master to the VPN subnet and required users only.
- Rotate `$POSTGRES_PASSWORD` and `$MASTER_DB_PASS` regularly.
