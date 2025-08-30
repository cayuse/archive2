# Archive Deployment Guide

A comprehensive guide for deploying the Archive music management system with optional Bucardo database replication and Syncthing file synchronization.

## Table of Contents

1. [Overview](#overview)
2. [Environment Setup](#environment-setup)
3. [Deployment Types](#deployment-types)
4. [Standalone Deployment](#standalone-deployment)
5. [Master Deployment](#master-deployment)
6. [Slave Deployment](#slave-deployment)
7. [Database Replication with Bucardo](#database-replication-with-bucardo)
8. [Troubleshooting](#troubleshooting)
9. [Security Considerations](#security-considerations)

## Overview

The Archive system supports three deployment configurations:

- **Standalone**: Single server deployment with no replication
- **Master**: Production server that can serve as a replication source
- **Slave**: Replication target that syncs from a master server

### Technology Stack

- **Application**: Ruby on Rails in Docker containers
- **Database**: PostgreSQL with optional Bucardo replication
- **Cache**: Redis
- **File Sync**: Syncthing (planned)
- **Networking**: WireGuard VPN recommended for inter-server communication

## Environment Setup

### Critical Prerequisites

1. **Docker and Docker Compose** must be installed and running
2. **Environment variables** must be exported before deployment
3. **Network connectivity** between master and slave (VPN recommended)
4. **Sufficient disk space** for PostgreSQL data and file storage

### Base Environment Variables (Required for ALL deployments)

These variables are needed regardless of deployment type:

```bash
# Rails application secrets
export RAILS_MASTER_KEY=your_32_character_rails_master_key_here

# Database configuration
export POSTGRES_PASSWORD=your_secure_database_password

# Host storage paths (must exist and be writable)
export HOST_STORAGE_PATH=/home/shared/psql_storage
export POSTGRES_DATA_PATH=/home/shared/psql_data

# Application port mapping
export ARCHIVE_PORT=3000

# Email configuration (optional but eliminates warnings)
export AWS_SES_SMTP_USERNAME=""
export AWS_SES_SMTP_PASSWORD=""
export AWS_SES_SMTP_HOST=""
export AWS_SES_SMTP_PORT=""
export AWS_SES_SMTP_DOMAIN=""
export MAILER_FROM_EMAIL=""
```

### Role-Specific Configuration

Choose ONE of the following role configurations:

#### Standalone Configuration
```bash
export ARCHIVE_ROLE=standalone
export APP_HOST=192.168.1.100              # This server's IP/hostname
export APP_PROTOCOL=http                    # Use https if SSL configured
export FORCE_SSL=false                      # Enable if using SSL
export ASSUME_SSL=false                     # Enable if behind SSL proxy
export FORGERY_ORIGIN_CHECK=false           # Enable for production
export ALLOW_ALL_HOSTS=true                 # Disable for production
export COMPOSE_FILE="docker-compose.yml"
```

#### Master Configuration
```bash
export ARCHIVE_ROLE=master
export APP_HOST=yourdomain.com              # Public domain or IP
export APP_PROTOCOL=https                   # Recommended for production
export FORCE_SSL=true                       # Enforce SSL connections
export ASSUME_SSL=true                      # Assume SSL from reverse proxy
export FORGERY_ORIGIN_CHECK=true            # Enable CSRF protection
export ALLOW_ALL_HOSTS=false                # Restrict to specific hosts
export COMPOSE_FILE="docker-compose.yml"
```

#### Slave Configuration
```bash
export ARCHIVE_ROLE=slave
export APP_HOST=192.168.1.161               # This slave's IP/hostname
export APP_PROTOCOL=http                     # Usually http for internal slaves
export FORCE_SSL=false                      # Slaves typically don't need SSL
export ASSUME_SSL=false                     # No reverse proxy SSL
export FORGERY_ORIGIN_CHECK=false           # Disable for internal testing
export ALLOW_ALL_HOSTS=true                 # Accept any Host header

# Docker Compose configuration
export COMPOSE_FILE="docker-compose.yml:docker-compose.replication.yml"

# Local Bucardo database connection
export BUCARDO_LOCAL_DB_HOST=db             # Docker service name
export BUCARDO_LOCAL_DB_PORT=5432           # PostgreSQL port
export BUCARDO_LOCAL_DB_NAME=bucardo        # Bucardo control database
export BUCARDO_LOCAL_DB_USER=bucardo        # Bucardo database user
export BUCARDO_LOCAL_DB_PASS=bucardo        # Bucardo database password

# Master database connection (must be reachable via VPN/LAN)
export MASTER_DB_HOST=192.168.1.201         # Master server IP address
export MASTER_DB_PORT=5432                  # Master PostgreSQL port
export MASTER_DB_NAME=archive_production    # Master database name
export MASTER_DB_USER=postgres              # Master database user
export MASTER_DB_PASS=$POSTGRES_PASSWORD    # Master database password

# Bucardo convenience variables (auto-derived from above)
export BUCARDO_MASTER_DB_HOST=$MASTER_DB_HOST
export BUCARDO_MASTER_DB_PORT=$MASTER_DB_PORT
export BUCARDO_MASTER_DB_NAME=$MASTER_DB_NAME
export BUCARDO_MASTER_DB_USER=$MASTER_DB_USER
export BUCARDO_MASTER_DB_PASS=$MASTER_DB_PASS
export BUCARDO_SYNC_DIRECTION=slave_from_master

# Bucardo sync frequency (in minutes) - how often to poll for changes
export BUCARDO_SYNC_FREQUENCY=5

# Logical replication (master-driven; slaves only need subscription)
# Master-only exports (used when preparing master for logical replication)
export REPL_USER=archive_replicator
export REPL_PASS=change-me
export PUB_NAME=pub_archive
```

### Environment Validation

After setting variables, verify them:

```bash
# Check all Archive-related variables
env | grep -E "(ARCHIVE|POSTGRES|APP_|BUCARDO|MASTER)" | sort

# Verify required directories exist
ls -la $HOST_STORAGE_PATH $POSTGRES_DATA_PATH
```

## Deployment Types

### Directory Structure

All deployments assume this directory structure:
```
~/archive2/
├── archive/                    # Main application directory
│   ├── docker-compose.yml     # Base compose file
│   ├── docker-compose.replication.yml  # Slave-specific overlay
│   ├── deploy_slave.sh        # Slave deployment script
│   ├── after_deploy_slave.sh  # Post-deployment sync setup
│   └── ...                    # Application files
└── temp_corrected_exports.sh  # Environment configuration
```

## Standalone Deployment

For single-server installations with no replication.

### Steps

1. **Set environment variables** (Base + Standalone configuration)
2. **Deploy the application**:

```bash
cd ~/archive2/archive
docker compose up -d --build
```

3. **Verify deployment**:

```bash
# Check container status
docker compose ps

# Verify application health
curl http://$APP_HOST:$ARCHIVE_PORT/up
# Should return: <!DOCTYPE html><html><body style="background-color: green"></body></html>

# Check logs
docker compose logs -f
```

## Master Deployment

For production servers that may serve as replication sources.

### Steps

1. **Set environment variables** (Base + Master configuration)
2. **Deploy the application**:

```bash
cd ~/archive2/archive
docker compose up -d --build
```

3. **Configure for replication** (if slaves will connect):

```bash
# Enable logical replication (one-time change, requires DB restart)
# These can be set via environment variables when starting compose:
#   PG_WAL_LEVEL=logical PG_MAX_WAL_SENDERS=10 PG_MAX_REPLICATION_SLOTS=10 docker compose up -d --build
# Or edit docker-compose.yml db.command block as needed.

# Verify wal_level
docker compose exec db psql -U postgres -c "SHOW wal_level;"  # should be 'logical' on master

# Create a dedicated replication user (example)
docker compose exec db psql -U postgres -d archive_production -c "CREATE ROLE ${REPL_USER:-archive_replicator} WITH LOGIN REPLICATION PASSWORD '${REPL_PASS:-change-me}';"
docker compose exec db psql -U postgres -d archive_production -c "GRANT USAGE ON SCHEMA public TO ${REPL_USER:-archive_replicator};"
docker compose exec db psql -U postgres -d archive_production -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO ${REPL_USER:-archive_replicator};"

# Grant SELECT on Archive tables (exclude internal/jukebox tables)
docker compose exec db psql -U postgres -d archive_production -c "GRANT SELECT ON TABLE \
  public.active_storage_attachments, public.active_storage_blobs, public.active_storage_variant_records, \
  public.albums, public.albums_genres, public.artists, public.artists_genres, public.genres, \
  public.playlists, public.playlists_songs, public.songs, public.system_settings, public.theme_assets, \
  public.themes, public.users \
TO ${REPL_USER:-archive_replicator};"

# Create publication (idempotent)
docker compose exec db psql -U postgres -d archive_production -c "DROP PUBLICATION IF EXISTS ${PUB_NAME:-pub_archive};"
docker compose exec db psql -U postgres -d archive_production -c "CREATE PUBLICATION ${PUB_NAME:-pub_archive} FOR TABLE \
  public.active_storage_attachments, public.active_storage_blobs, public.active_storage_variant_records, \
  public.albums, public.albums_genres, public.artists, public.artists_genres, public.genres, \
  public.playlists, public.playlists_songs, public.songs, public.system_settings, public.theme_assets, \
  public.themes, public.users;"
```

4. **Verify deployment** (same as standalone)

## Slave Deployment

For replication targets that sync from a master server.

### Overview

Slave deployment is a two-phase process:
1. **Initial deployment**: Sets up containers and basic configuration
2. **Replication setup**: Syncs data from master and configures ongoing replication

### Phase 1: Initial Deployment

1. **Set environment variables** (Base + Slave configuration)

2. **Run the slave deployment script**:

```bash
cd ~/archive2/archive
./deploy_slave.sh
```

This script will:
- Validate environment variables
- Create required directories
- Build custom PostgreSQL image with Bucardo support
- Start all containers (PostgreSQL, Redis, Rails, Bucardo)
- Set up Bucardo database and user
- Install Bucardo schema

3. **Verify initial deployment**:

```bash
# Check all containers are running
docker compose ps

# Verify Bucardo is working
docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo status

# Test connectivity to master
psql -h $MASTER_DB_HOST -p $MASTER_DB_PORT -U $MASTER_DB_USER -d $MASTER_DB_NAME -c "\l"
```

### Phase 2: Replication Setup

After successful initial deployment, run the automated sync setup:

```bash
cd ~/archive2/archive
./after_deploy_slave.sh
```

This script will:
1. **Dump master database** - Creates complete backup of master data
2. **Restore to slave** - Loads master data into local database
3. **Verify data integrity** - Compares record counts
4. **Configure Bucardo replication** - Sets up ongoing sync
5. **Test replication** - Inserts test record and verifies sync

### Expected Output

The script provides colored output and progress indicators:
- 🔄 Starting automated slave sync setup
- 📥 Dumping master database
- 📤 Restoring data to slave
- ✅ Verifying data copy
- 🔧 Setting up Bucardo replication
- 🧪 Testing replication
- ✨ Setup complete

### Post-Deployment Verification

```bash
# Check sync status
docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo status archive_sync

# Monitor replication logs
docker compose logs bucardo -f

# Compare data counts
echo "Master:" && psql -h $MASTER_DB_HOST -p $MASTER_DB_PORT -U $MASTER_DB_USER -d $MASTER_DB_NAME -t -c "SELECT COUNT(*) FROM songs;"
echo "Slave:" && docker compose exec -T db psql -U postgres -d archive_production -t -c "SELECT COUNT(*) FROM songs;"
# Logical replication: create subscription on slave (idempotent)
docker compose exec -T db psql -U postgres -d archive_production -c "DROP SUBSCRIPTION IF EXISTS ${SUB_NAME:-sub_archive};"
docker compose exec -T db psql -U postgres -d archive_production -c "CREATE SUBSCRIPTION ${SUB_NAME:-sub_archive} CONNECTION 'host=${MASTER_DB_HOST} port=${MASTER_DB_PORT} dbname=${MASTER_DB_NAME} user=${REPL_USER:-archive_replicator} password=${REPL_PASS:-change-me}' PUBLICATION ${PUB_NAME:-pub_archive} WITH (copy_data=false, create_slot=true, slot_name='${SUB_SLOT_NAME:-sub_archive_slot}');"

# Verify
docker compose exec -T db psql -U postgres -d archive_production -c "SELECT subname, status, last_msg_send_time, last_msg_receipt_time FROM pg_stat_subscription;"
```

## Database Replication with Bucardo

### Architecture

- **Master**: Standard Archive deployment with PostgreSQL
- **Slave**: Archive deployment + Bucardo container
- **Replication**: Bidirectional PostgreSQL-to-PostgreSQL sync
- **Network**: VPN recommended (WireGuard, OpenVPN, etc.)

### Replication Flow

1. **Initial sync**: Master database dumped and restored to slave
2. **Ongoing sync**: Bucardo polls master for changes at configured intervals
3. **Polling frequency**: Controlled by `BUCARDO_SYNC_FREQUENCY` (default: 5 minutes)
4. **Conflict resolution**: Bucardo handles conflicts with configurable rules
5. **Health monitoring**: Built-in status and logging

### Replication Method

The slave uses **polling-based replication** with the following characteristics:
- **No triggers on master**: Master database remains unchanged
- **Independent polling**: Each slave polls master independently
- **Configurable frequency**: Set via `BUCARDO_SYNC_FREQUENCY` environment variable
- **Multi-slave friendly**: Multiple slaves can connect without interference
- **Connection resilient**: Handles network disconnections gracefully

### Manual Replication Commands

If you need to manually configure replication or troubleshoot:

```bash
# Add databases to Bucardo
docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo add database local \
  dbname=archive_production host=db port=5432 \
  user=postgres pass=$POSTGRES_PASSWORD

docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo add database master \
  dbname=$MASTER_DB_NAME host=$MASTER_DB_HOST port=$MASTER_DB_PORT \
  user=$MASTER_DB_USER pass=$MASTER_DB_PASS

# Add tables for replication
docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo add all tables --db=local,master

# Create and start sync
docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo add sync archive_sync \
  relgroup=default dbs=local,master

docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo start archive_sync
```

### Monitoring Replication

```bash
# Check sync status
docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo status archive_sync

# View active syncs
docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo list syncs

# Monitor logs
docker compose logs bucardo -f

# Check for conflicts
docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo list conflicts
```

## Troubleshooting

### Common Issues

#### 1. Container Startup Failures

```bash
# Check container logs
docker compose logs [service_name]

# Rebuild containers
docker compose down
docker compose build --no-cache
docker compose up -d
```

#### 2. Database Connection Issues

```bash
# Test local database
docker compose exec db psql -U postgres -l

# Test master database (from slave)
psql -h $MASTER_DB_HOST -p $MASTER_DB_PORT -U $MASTER_DB_USER -l

# Check network connectivity
ping $MASTER_DB_HOST
nc -zv $MASTER_DB_HOST $MASTER_DB_PORT
```

#### 3. Bucardo Issues

```bash
# Check Bucardo status
docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo status

# Restart Bucardo daemon
docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo restart

# Check Bucardo configuration
docker compose exec bucardo cat /var/lib/bucardo/.bucardorc

# View Bucardo logs
docker compose exec bucardo cat /var/log/bucardo/bucardo.log
```

#### 4. Environment Variable Issues

```bash
# Check if variables are set
env | grep -E "(ARCHIVE|POSTGRES|BUCARDO|MASTER)"

# Re-source configuration
source ~/archive2/temp_corrected_exports.sh

# Verify in containers
docker compose exec bucardo env | grep BUCARDO
```

#### 5. Permission Issues

```bash
# Fix directory permissions
sudo chown -R $USER:$USER $HOST_STORAGE_PATH $POSTGRES_DATA_PATH
sudo chmod 755 $HOST_STORAGE_PATH $POSTGRES_DATA_PATH
```

### Debug Commands

```bash
# Container health checks
docker compose ps
docker compose exec db pg_isready -U postgres
docker compose exec bucardo pg_isready -h db -U bucardo -d bucardo

# Application health
curl http://$APP_HOST:$ARCHIVE_PORT/up

# Database queries
docker compose exec db psql -U postgres -d archive_production -c "\dt"
docker compose exec bucardo psql -h db -U bucardo -d bucardo -c "\dt"

# Network tests
docker compose exec bucardo ping db
docker compose exec bucardo pg_isready -h $MASTER_DB_HOST -p $MASTER_DB_PORT -U $MASTER_DB_USER
```

### Log Locations

- **Application logs**: `docker compose logs archive`
- **Database logs**: `docker compose logs db`
- **Bucardo logs**: `docker compose logs bucardo`
- **Bucardo daemon log**: `/var/log/bucardo/bucardo.log` (inside container)

## Security Considerations

### Network Security

1. **Use VPN for inter-server communication**
   - WireGuard recommended for performance and security
   - Never expose PostgreSQL directly to the internet
   - Configure firewall rules to restrict access

2. **PostgreSQL security**
   - Use strong passwords for `POSTGRES_PASSWORD`
   - Limit `pg_hba.conf` to specific IP ranges
   - Consider SSL connections for production

3. **Application security**
   - Use strong `RAILS_MASTER_KEY`
   - Enable CSRF protection in production (`FORGERY_ORIGIN_CHECK=true`)
   - Restrict allowed hosts in production (`ALLOW_ALL_HOSTS=false`)
   - Use HTTPS in production (`FORCE_SSL=true`)

### Data Security

1. **Backup strategy**
   - Regular `pg_dump` backups
   - Test backup restoration procedures
   - Store backups securely and off-site

2. **Access control**
   - Limit database user privileges
   - Rotate passwords regularly
   - Monitor access logs

3. **File system security**
   - Secure storage directory permissions
   - Consider encrypted file systems
   - Monitor disk usage

### Container Security

1. **Image security**
   - Use official base images
   - Keep images updated
   - Scan for vulnerabilities

2. **Runtime security**
   - Run containers as non-root users where possible
   - Limit container capabilities
   - Monitor container logs

### Monitoring

1. **Health checks**
   - Monitor application `/up` endpoint
   - Check database connectivity
   - Monitor Bucardo sync status

2. **Alerting**
   - Set up alerts for container failures
   - Monitor replication lag
   - Alert on disk space issues

## Future Enhancements

### Planned Features

1. **Syncthing Integration**
   - File synchronization between servers
   - Configuration templates
   - Monitoring and alerting

2. **Automated Failover**
   - Health checks and automatic promotion
   - DNS updates for seamless failover
   - Data consistency verification

3. **Monitoring Dashboard**
   - Real-time replication status
   - Performance metrics
   - Historical trend analysis

4. **Backup Automation**
   - Scheduled backups
   - Automated cleanup
   - Cross-site replication

---

## Quick Reference

### Common Commands

```bash
# Deploy standalone/master
cd ~/archive2/archive && docker compose up -d --build

# Deploy slave
cd ~/archive2/archive && ./deploy_slave.sh && ./after_deploy_slave.sh

# Check status
docker compose ps
docker compose logs -f

# Restart services
docker compose restart [service]

# Update deployment
git pull && docker compose up -d --build

# Backup database
pg_dump -h $MASTER_DB_HOST -U $MASTER_DB_USER -d $MASTER_DB_NAME > backup.sql

# Restore database
psql -h localhost -U postgres -d archive_production < backup.sql
```

### Important Files

- `~/archive2/temp_corrected_exports.sh` - Environment configuration
- `~/archive2/archive/deploy_slave.sh` - Slave deployment script
- `~/archive2/archive/after_deploy_slave.sh` - Replication setup script
- `~/archive2/postgres_notes.md` - Detailed PostgreSQL commands

This deployment guide provides a complete foundation for deploying and managing the Archive system with optional replication capabilities.