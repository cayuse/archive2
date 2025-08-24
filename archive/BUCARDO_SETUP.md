# Bucardo Replication Setup for Archive System

This document describes how to set up Bucardo database replication between master and slave archive systems.

## Architecture

- **Master**: Primary archive system (cavaforgepad - 192.168.1.200)
- **Slaves**: Secondary archive systems (jukebox - 192.168.1.201, etc.)
- **Bucardo**: PostgreSQL multi-master replication system running in containers

## Quick Start

### 1. Choose Your Role

**For Master (cavaforgepad):**
```bash
source env.common
source env.master
```

**For Slave (jukebox):**
```bash
source env.common
source env.slave
```

### 2. Deploy the System

**For Master (existing system):**
```bash
# Use existing deploy.sh
./deploy.sh
```

**For Slave (fresh system):**
```bash
# Use slave-specific deployment script
./deploy_slave.sh
```

### 3. Manual Start (Alternative)

```bash
# Build and start all services including Bucardo
docker compose up -d --build

# Or start just the database and Bucardo first
docker compose up -d db bucardo
```

### 3. Check Status

```bash
# Check all services
docker compose ps

# Check Bucardo logs
docker compose logs bucardo

# Check Bucardo status inside container
docker compose exec bucardo bucardo status
```

## Environment Configuration

### Master Configuration (env.master)
- `ARCHIVE_ROLE=master`
- `APP_HOST=192.168.1.200`
- `BUCARDO_SYNC_DIRECTION=master_to_slaves`

### Slave Configuration (env.slave)
- `ARCHIVE_ROLE=slave`
- `APP_HOST=192.168.1.201`
- `BUCARDO_SYNC_DIRECTION=slave_from_master`

### Common Configuration (env.common)
- Database credentials
- Bucardo local database settings
- Rails configuration

## How It Works

1. **Bucardo Container**: Runs as a separate service with all Perl dependencies
2. **Database Connection**: Bucardo connects to both local and master databases
3. **Automatic Setup**: Bucardo automatically installs its schema and configures replication
4. **Health Monitoring**: Built-in health checks ensure services are running

## Deployment Scripts

### deploy.sh (Master)
- Standard deployment for existing master systems
- Assumes database already exists and has data
- Runs on port 80 (production) or 3000 (development)

### deploy_slave.sh (Slave)
- Specialized deployment for fresh slave systems
- Creates empty database from scratch
- Runs database migrations automatically
- Sets up Bucardo replication automatically
- Runs on port 3000 (development mode)

## Troubleshooting

### Bucardo Won't Start
```bash
# Check logs
docker compose logs bucardo

# Check database connectivity
docker compose exec bucardo psql -h db -U bucardo -d bucardo -c "SELECT 1;"
```

### Replication Issues
```bash
# Check Bucardo status
docker compose exec bucardo bucardo status

# Check sync status
docker compose exec bucardo bucardo list syncs
```

### Database Connection Issues
```bash
# Verify PostgreSQL is running
docker compose ps db

# Check database health
docker compose exec db pg_isready -U postgres
```

## Adding New Slaves

1. Copy the `env.slave` file to the new machine
2. Update `APP_HOST` to the new machine's IP
3. Update `MASTER_DB_HOST` if the master IP changes
4. Run `source env.slave` and `docker compose up -d`

## Security Notes

- Bucardo user has superuser privileges (required for replication)
- Database passwords are stored in environment variables
- Consider using Docker secrets for production deployments
- Ensure proper network isolation between master and slaves

## Performance Considerations

- Bucardo adds minimal overhead to PostgreSQL
- Replication is asynchronous by default
- Monitor `bucardo.log` for performance issues
- Consider adjusting sync intervals based on your needs
