# Archive Deployment Guide

A comprehensive guide for deploying the Archive music management system with PostgreSQL logical replication and Syncthing file synchronization.

## Table of Contents

1. [Overview](#overview)
2. [Environment Setup](#environment-setup)
   - [Creating Rails Master Key and Credentials](#creating-rails-master-key-and-credentials-critical-first-step)
3. [Deployment Types](#deployment-types)
4. [Standalone Deployment](#standalone-deployment)
5. [Master Deployment](#master-deployment)
6. [Slave Deployment](#slave-deployment)
7. [Database Replication with PostgreSQL Logical Replication](#database-replication-with-postgresql-logical-replication)
8. [Player Service Installation](#player-service-installation)
9. [Troubleshooting](#troubleshooting)
10. [Security Considerations](#security-considerations)

## Overview

The Archive system supports three deployment configurations:

- **Standalone**: Single server deployment with no replication
- **Master**: Production server that can serve as a replication source
- **Slave**: Replication target that syncs from a master server

### Technology Stack

- **Application**: Ruby on Rails in Docker containers
- **Database**: PostgreSQL with logical replication
- **Cache**: Redis
- **File Sync**: Syncthing (planned)
- **Networking**: WireGuard VPN recommended for inter-server communication

## Environment Setup

### Critical Prerequisites

1. **Docker and Docker Compose** must be installed and running
2. **Environment variables** must be exported before deployment
3. **Network connectivity** between master and slave (VPN recommended)
4. **Sufficient disk space** for PostgreSQL data and file storage

### Creating Rails Master Key and Credentials (CRITICAL FIRST STEP)

**⚠️ IMPORTANT**: Before setting environment variables, you MUST create the Rails master key and credentials file. The application ships without these security files and they must be generated for each deployment.

#### Method 1: Using Temporary Docker Container (Recommended for Production)
####   this method shows archive, but you need to do this procedure in both archive and jukebox 
####   or copy the credentials from archive to jukebox
If you're deploying directly with Docker and don't have a local Ruby environment:

```bash
# Navigate to the archive directory
cd ~/archive2/archive

# Start a temporary container with bundle install capability
docker run --rm -it -v "$(pwd):/app" -w /app ruby:3.2.5 bash

# Inside the container:
bundle install

# First, generate the master key
rails credentials:edit
# Then create the encrypted credentials file
VISUAL="code --wait" bin/rails credentials:edit
# This process creates:
# - config/master.key (32-character key) - created by rails secret
# - config/credentials.yml.enc (encrypted secrets file) - created by credentials:edit
# - save the master key, it will be displayed to you, and you'll need it for deployment
# Exit the container
exit

# Back on host - copy the master key value for your environment variable 
cat config/master.key  #may require sudo
```

#### Method 2: Using Local Rails Environment

If you have Ruby and Rails installed locally:

```bash
cd ~/archive2/archive

# Install dependencies
bundle install

# First, generate the master key
bin/rails secret > config/master.key

# Then create the encrypted credentials file (opens editor)
bin/rails credentials:edit

# This process creates:
# - config/master.key (32-character key) - created by rails secret
# - config/credentials.yml.enc (encrypted secrets file) - created by credentials:edit
# Copy the master key value:
cat config/master.key
```

#### Method 3: Quick Development Setup (Development Only)

For development environments only (not recommended for production):

```bash
cd ~/archive2/archive

# Generate master key using Rails (preferred method)
echo "changeme-dev-key-only" > config/master.key

# Create basic encrypted credentials
EDITOR="echo '# Development secrets'" bin/rails credentials:edit
```

**⚠️ Warning**: This method creates a weak development key. For production, always use Method 1 or Method 2 above.

**🔒 Security Notes:**
- The `config/master.key` file contains your encryption key - keep it secure!
- Never commit `config/master.key` to version control
- Use the key value from this file as your `RAILS_MASTER_KEY` environment variable
- Each deployment should have its own unique master key

### Base Environment Variables (Required for ALL deployments)

These variables are needed regardless of deployment type:

```bash
# Rails application secrets (use the exact key from config/master.key created in section above)
export RAILS_MASTER_KEY=your_actual_master_key_from_config_master_key_file

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
export COMPOSE_FILE="docker-compose.yml"

# Master database connection (must be reachable via VPN/LAN)
export MASTER_DB_HOST=192.168.1.201         # Master server IP address
export MASTER_DB_PORT=5432                  # Master PostgreSQL port
export MASTER_DB_NAME=archive_production    # Master database name
export MASTER_DB_USER=postgres              # Master database user
export MASTER_DB_PASS=$POSTGRES_PASSWORD    # Master database password

# Logical replication configuration
export REPLICATION_MODE=logical             # Use PostgreSQL logical replication
export REPL_USER=archive_replicator         # Replication user on master
export REPL_PASS=change-me                  # Replication user password
export PUB_NAME=pub_archive                 # Publication name on master
export SUB_NAME=sub_archive                 # Subscription name on slave
export SUB_SLOT_NAME=sub_archive_slot       # Replication slot name
```

### Environment Validation

After setting variables, verify them:

```bash
# Check all Archive-related variables
env | grep -E "(ARCHIVE|POSTGRES|APP_|MASTER|REPL_)" | sort

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

# ⚠️ SECURITY: If you used the default "change-me" password above, change it now!
# Update replication user password to something secure:
docker compose exec db psql -U postgres -d archive_production -c "ALTER ROLE ${REPL_USER:-archive_replicator} PASSWORD 'your_secure_replication_password_here';"

# Ensure all tables have primary keys (required for logical replication DELETEs)
docker compose exec db psql -U postgres -d archive_production -c "ALTER TABLE albums_genres ADD CONSTRAINT albums_genres_pkey PRIMARY KEY (album_id, genre_id);" 2>/dev/null || true
docker compose exec db psql -U postgres -d archive_production -c "ALTER TABLE artists_genres ADD CONSTRAINT artists_genres_pkey PRIMARY KEY (artist_id, genre_id);" 2>/dev/null || true
docker compose exec db psql -U postgres -d archive_production -c "ALTER TABLE playlists_songs ADD CONSTRAINT playlists_songs_pkey PRIMARY KEY (playlist_id, song_id);" 2>/dev/null || true

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

### 🚀 Quick Start for Slave Deployment

**For convenience, we provide a template file that contains all required environment variables:**

1. **Copy the template**: 
   ```bash
   cp ~/archive2/archive/slave_exports_template.sh ~/my_slave_config.sh
   ```

2. **Edit with your values**:
   ```bash
   nano ~/my_slave_config.sh
   ```
   - Change `APP_HOST` to your slave's IP address
   - Change `MASTER_DB_HOST` to your master's IP address  
   - Set `RAILS_MASTER_KEY` (see [Creating Rails Master Key and Credentials](#creating-rails-master-key-and-credentials-critical-first-step) section above)
   - Set `POSTGRES_PASSWORD` to a secure password
   - Set `REPL_PASS` to match your master's replication user password
   - Update AWS SES settings if using email features

3. **Deploy**:
   ```bash
   source ~/my_slave_config.sh
   cd ~/archive2/archive
   ./deploy_slave.sh && ./after_deploy_slave.sh
   ```

**⚠️ Security Note**: Save your config file OUTSIDE the git repository to avoid committing passwords!

### Manual Configuration (Alternative)

If you prefer to set environment variables manually:

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
- Start all containers (PostgreSQL, Redis, Rails)

3. **Verify initial deployment**:

```bash
# Check all containers are running
docker compose ps

# Verify DB and app are healthy

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
4. **Create logical replication subscription** - Sets up ongoing sync
5. **Test replication** - Inserts test record and verifies sync

### Expected Output

The script provides colored output and progress indicators:
- 🔄 Starting automated slave sync setup
- 📥 Dumping master database
- 📤 Restoring data to slave
- ✅ Verifying data copy
- 🔧 Creating logical replication subscription
- 🧪 Testing replication
- ✨ Setup complete

### Post-Deployment Verification

```bash
# Check subscription status
docker compose exec -T db psql -U postgres -d archive_production -c "SELECT * FROM pg_stat_subscription;"

# Compare data counts
echo "Master:" && psql -h $MASTER_DB_HOST -p $MASTER_DB_PORT -U $MASTER_DB_USER -d $MASTER_DB_NAME -t -c "SELECT COUNT(*) FROM songs;"
echo "Slave:" && docker compose exec -T db psql -U postgres -d archive_production -t -c "SELECT COUNT(*) FROM songs;"

# Manually recreate subscription if needed (idempotent)
docker compose exec -T db psql -U postgres -d archive_production -c "DROP SUBSCRIPTION IF EXISTS ${SUB_NAME:-sub_archive};"
docker compose exec -T db psql -U postgres -d archive_production -c "CREATE SUBSCRIPTION ${SUB_NAME:-sub_archive} CONNECTION 'host=${MASTER_DB_HOST} port=${MASTER_DB_PORT} dbname=${MASTER_DB_NAME} user=${REPL_USER:-archive_replicator} password=${REPL_PASS:-change-me}' PUBLICATION ${PUB_NAME:-pub_archive} WITH (copy_data=false, create_slot=true, slot_name='${SUB_SLOT_NAME:-sub_archive_slot}');"

# Verify subscription health
docker compose exec -T db psql -U postgres -d archive_production -c "SELECT subname, status, last_msg_send_time, last_msg_receipt_time FROM pg_stat_subscription;"
```

## Database Replication with PostgreSQL Logical Replication

### Architecture

- **Master**: Standard Archive deployment with PostgreSQL
- **Slave**: Archive deployment with subscription
- **Replication**: Logical replication (publication/subscription)
- **Network**: VPN recommended (WireGuard, OpenVPN, etc.)

### Multiple Slaves Support

PostgreSQL logical replication naturally supports multiple slaves connecting to one master:

#### How It Works:
- **One Publication**: The master has ONE publication (`pub_archive`) that all slaves subscribe to
- **One Replication User**: All slaves use the SAME replication user (`archive_replicator`)
- **Unique Subscriptions**: Each slave creates its OWN subscription with a UNIQUE slot name
- **Independent Connections**: Slaves connect independently - one going down doesn't affect others

#### Slot Management:
- **Slot Name Pattern**: Each slave should use a unique `SUB_SLOT_NAME` (e.g., `slave_001_slot`, `slave_002_slot`)
- **Default Limits**: PostgreSQL allows 10 concurrent replication slots by default
- **Automatic Creation**: Slots are created automatically when slaves connect
- **Automatic Cleanup**: Slots are removed when subscriptions are dropped

### Replication Flow

1. **Initial sync**: Master database dumped and restored to slave
2. **Ongoing sync**: Slave streams changes from master publication
3. **Latency**: Near real-time
4. **Health monitoring**: `pg_stat_subscription` and `pg_replication_slots`

### Replication Method

The slave uses **PostgreSQL logical replication** with the following characteristics:
- **No triggers on master**: Master database remains unchanged
- **Streaming replication**: Changes are streamed in near real-time
- **Publisher/Subscriber model**: Master publishes changes, slave subscribes
- **Multi-slave friendly**: Multiple slaves can subscribe independently
- **Connection resilient**: Handles network disconnections gracefully
- **WAL-based**: Uses PostgreSQL's Write-Ahead Log for change detection

### Manual Replication Commands (Logical)

If you need to manually configure replication or troubleshoot:

```bash
# Create subscription on slave
docker compose exec -T db psql -U postgres -d archive_production -c "DROP SUBSCRIPTION IF EXISTS ${SUB_NAME:-sub_archive};"
docker compose exec -T db psql -U postgres -d archive_production -c "CREATE SUBSCRIPTION ${SUB_NAME:-sub_archive} CONNECTION 'host=${MASTER_DB_HOST} port=${MASTER_DB_PORT} dbname=${MASTER_DB_NAME} user=${REPL_USER:-archive_replicator} password=${REPL_PASS:-change-me}' PUBLICATION ${PUB_NAME:-pub_archive} WITH (copy_data=false, create_slot=true, slot_name='${SUB_SLOT_NAME:-sub_archive_slot}');"
```

### Monitoring Replication

```bash
# Check subscription status (on slave)
docker compose exec -T db psql -U postgres -d archive_production -c "SELECT * FROM pg_stat_subscription;"

# Check replication slots (on master)
psql -h $MASTER_DB_HOST -p $MASTER_DB_PORT -U $MASTER_DB_USER -d $MASTER_DB_NAME -c "SELECT * FROM pg_replication_slots;"

# Monitor replication lag
docker compose exec -T db psql -U postgres -d archive_production -c "SELECT now() - last_msg_receipt_time AS lag FROM pg_stat_subscription;"

# Check publication tables (on master)
psql -h $MASTER_DB_HOST -p $MASTER_DB_PORT -U $MASTER_DB_USER -d $MASTER_DB_NAME -c "SELECT * FROM pg_publication_tables WHERE pubname = '${PUB_NAME:-pub_archive}';"
```

### Managing Multiple Slaves

For managing multiple slaves, use the provided management script on the **master server**:

```bash
# Copy management script to master server
scp ~/archive2/manage_replication.sh master-server:~/

# On master server:
chmod +x manage_replication.sh

# List all connected slaves
./manage_replication.sh list

# Show detailed status
./manage_replication.sh status

# Show slot usage and limits
./manage_replication.sh limits

# Remove a dead/inactive slave slot
./manage_replication.sh remove slave_002_slot

# Clean up all inactive slots
./manage_replication.sh cleanup
```

#### Slave Naming Convention

For multiple slaves, customize the slot name in each slave's config:

```bash
# Slave 1:
export SUB_SLOT_NAME=slave_001_slot

# Slave 2:
export SUB_SLOT_NAME=slave_002_slot

# Slave 3:
export SUB_SLOT_NAME=slave_003_slot
```

#### When Running Test Deployments

**Q: Will each test run create a new slot?**
- **No** - If you use the same `SUB_SLOT_NAME`, it will reuse the existing slot
- **Yes** - Only if you change the `SUB_SLOT_NAME` between runs

**Q: How to avoid cluttering the master with test slots?**
1. **Use consistent naming** for test slaves (e.g., `test_slave_slot`)
2. **Clean up after testing**: `./manage_replication.sh remove test_slave_slot`
3. **Use the cleanup command**: `./manage_replication.sh cleanup` (removes inactive slots)

**Q: Will reusing slots cause issues?**
- **No** - PostgreSQL handles slot reuse gracefully
- **Benefits** - No accumulation of dead slots on master
- **Same credentials** - All slaves use the same replication user

## Player Service Installation

The Archive system includes a Python-based music player service that handles audio playback. This service connects to the jukebox via Redis and streams audio using MPV.

### Overview

The player service:
- Connects to jukebox Redis queue for commands
- Fetches audio streams from jukebox API  
- Uses MPV for high-quality audio playback
- Runs as a systemd service for reliability

### Installation Steps

⚠️ **Important**: The player installation process requires manual configuration. For detailed installation instructions, see:

**📖 [Player Installation Guide](./player/README.md)**

The player README contains comprehensive instructions for:
- Python virtual environment setup
- Dependency installation
- Configuration file creation
- Systemd service installation
- Audio system requirements

### Quick Installation Summary

1. **Install Dependencies**:
   ```bash
   sudo apt install mpv python3.12 python3.12-venv
   ```

2. **Set up Python Environment**:
   ```bash
   cd ~/archive2/player
   python3.12 -m venv .venv
   source .venv/bin/activate
   pip install -r requirements.txt
   ```

3. **Create Configuration**:
   ```bash
   # Create .env file with Redis and API settings
   # See player/README.md for full configuration details
   ```

4. **Install as System Service**:
   ```bash
   # Configure systemd service
   # Ensure user has audio system access
   # See player/README.md for complete service setup
   ```

### Audio System Requirements

⚠️ **Critical**: The player service requires access to the audio subsystem. The service user must have:

- Access to audio devices (ALSA/PulseAudio/PipeWire)
- Proper audio group membership
- Runtime audio session access

**Note**: Audio configuration varies by Linux distribution and audio system. Consult your system's audio documentation if you encounter audio permission issues.

### Configuration Notes

- **Redis Connection**: Must connect to same Redis instance as jukebox
- **API Endpoint**: Direct connection to jukebox API recommended
- **Audio Output**: Configurable via MPV audio device settings
- **Service User**: Can run as console user or dedicated service user

For complete installation procedures and troubleshooting, refer to the dedicated [Player README](./player/README.md).

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

#### 3. Logical Replication Issues

```bash
# Check subscription status
docker compose exec -T db psql -U postgres -d archive_production -c "SELECT * FROM pg_stat_subscription;"

# Check replication slots on master
psql -h $MASTER_DB_HOST -p $MASTER_DB_PORT -U $MASTER_DB_USER -d $MASTER_DB_NAME -c "SELECT slot_name, active, restart_lsn FROM pg_replication_slots;"
```

#### 4. Environment Variable Issues

```bash
# Check if variables are set
env | grep -E "(ARCHIVE|POSTGRES|MASTER|REPL_)"

# Re-source configuration
source ~/archive2/temp_corrected_exports.sh

# Verify database settings
docker compose exec -T db psql -U postgres -c "SHOW wal_level;"
```

#### 5. Permission Issues

```bash
# Fix directory permissions
sudo chown -R $USER:$USER $HOST_STORAGE_PATH $POSTGRES_DATA_PATH
sudo chmod 755 $HOST_STORAGE_PATH $POSTGRES_DATA_PATH
```

#### 6. Rails Credentials Issues

```bash
# Missing or invalid master key
# Error: `Rails couldn't decrypt credentials`
# Solution: Recreate credentials using temporary container method above

# Check if credentials files exist
ls -la ~/archive2/archive/config/master.key
ls -la ~/archive2/archive/config/credentials.yml.enc

# Regenerate credentials if missing
cd ~/archive2/archive
docker run --rm -it -v "$(pwd):/app" -w /app ruby:3.3.8 bash
# Inside container: gem install bundler && bundle install && bundle exec rails secret > config/master.key && bundle exec rails credentials:edit

# Verify master key matches environment variable
echo "File: $(cat config/master.key)"
echo "Env:  $RAILS_MASTER_KEY"
```

### Debug Commands

```bash
# Container health checks
docker compose ps
docker compose exec db pg_isready -U postgres

# Application health
curl http://$APP_HOST:$ARCHIVE_PORT/up

# Database queries
docker compose exec db psql -U postgres -d archive_production -c "\dt"

# Network tests from slave to master
nc -zv $MASTER_DB_HOST $MASTER_DB_PORT
PGPASSWORD=$MASTER_DB_PASS psql -h $MASTER_DB_HOST -p $MASTER_DB_PORT -U $MASTER_DB_USER -d $MASTER_DB_NAME -c "SELECT 1;"
```

### Log Locations

- **Application logs**: `docker compose logs archive`
- **Database logs**: `docker compose logs db`
- **PostgreSQL logs**: Check within database container or mounted volume

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
   - Monitor subscription status

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