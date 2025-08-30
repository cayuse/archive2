# PostgreSQL Connection Commands

## Overview
This document contains common PostgreSQL connection commands for the Archive system with Bucardo replication.

## Environment
- **Local Slave IP**: 192.168.1.161
- **Master IP**: 192.168.1.201
- **Database**: archive_production
- **User**: postgres
- **Password**: password

## Local Database Connections (Slave Machine)

### Basic Connection
```bash
# Connect to local archive_production database
docker compose exec db psql -U postgres -d archive_production

# Connect with explicit host (same result)
docker compose exec db psql -h localhost -U postgres -d archive_production
```

### Quick Data Checks
```bash
# List all databases
docker compose exec db psql -U postgres -c "\l"

# List tables in archive_production
docker compose exec db psql -U postgres -d archive_production -c "\dt"

# Count records in songs table
docker compose exec db psql -U postgres -d archive_production -c "SELECT COUNT(*) FROM songs;"

# Check recent songs
docker compose exec db psql -U postgres -d archive_production -c "SELECT id, title, created_at FROM songs ORDER BY created_at DESC LIMIT 5;"
```

## Remote Master Database Connections

### Basic Connection to Master
```bash
# Connect to master's archive_production database from slave
docker compose exec db psql -h 192.168.1.201 -U postgres -d archive_production

# Direct connection from host (outside container)
psql -h 192.168.1.201 -p 5432 -U postgres -d archive_production
```

### Quick Master Data Checks
```bash
# List databases on master
psql -h 192.168.1.201 -p 5432 -U postgres -c "\l"

# Count records on master
psql -h 192.168.1.201 -p 5432 -U postgres -d archive_production -c "SELECT COUNT(*) FROM songs;"

# Check master tables
psql -h 192.168.1.201 -p 5432 -U postgres -d archive_production -c "\dt"
```

## Bucardo Container Connections

### From Bucardo Container
```bash
# Connect to local archive_production from bucardo container
docker compose exec bucardo psql -h db -U postgres -d archive_production

# Connect to master archive_production from bucardo container  
docker compose exec bucardo psql -h 192.168.1.201 -U postgres -d archive_production

# Connect to bucardo control database
docker compose exec bucardo psql -h db -U bucardo -d bucardo
```

## Data Comparison Commands

### Compare Local vs Master
```bash
# Quick count comparison
echo "=== LOCAL SLAVE ===" && \
docker compose exec db psql -U postgres -d archive_production -c "SELECT COUNT(*) FROM songs;" -t && \
echo "=== REMOTE MASTER ===" && \
docker compose exec db psql -h 192.168.1.201 -U postgres -d archive_production -c "SELECT COUNT(*) FROM songs;" -t
```

### Detailed Comparison
```bash
# Compare table structures
echo "=== LOCAL TABLES ===" && \
docker compose exec db psql -U postgres -d archive_production -c "\dt" && \
echo "=== MASTER TABLES ===" && \
psql -h 192.168.1.201 -p 5432 -U postgres -d archive_production -c "\dt"
```

## Network Testing

### Test Connectivity
```bash
# Test basic network connectivity to master
ping 192.168.1.201

# Test PostgreSQL port specifically
nc -zv 192.168.1.201 5432

# Test from within db container
docker compose exec db pg_isready -h 192.168.1.201 -p 5432 -U postgres
```

## Bucardo-Specific Commands

### Bucardo Status and Management
```bash
# Check Bucardo status (should work after CLI fix)
docker compose exec bucardo bucardo status

# List Bucardo databases
docker compose exec bucardo bucardo list databases

# List Bucardo syncs
docker compose exec bucardo bucardo list syncs

# View Bucardo logs
docker compose logs bucardo

# Check Bucardo control database
docker compose exec bucardo psql -h db -U bucardo -d bucardo -c "\dt"
```

### Bucardo Database Setup Commands
```bash
# Add local database to Bucardo
docker compose exec bucardo bucardo add database local \
  dbname=archive_production host=db port=5432 \
  user=postgres pass=password

# Add master database to Bucardo
docker compose exec bucardo bucardo add database master \
  dbname=archive_production host=192.168.1.201 port=5432 \
  user=postgres pass=password
```

## Troubleshooting

### Common Issues
1. **Connection refused**: Check if PostgreSQL is running and accepting connections
2. **Authentication failed**: Verify password and pg_hba.conf settings
3. **Database doesn't exist**: Ensure database was created and migrated

### Debug Commands
```bash
# Check container status
docker compose ps

# Check container logs
docker compose logs db
docker compose logs bucardo

# Check environment variables in containers
docker compose exec bucardo env | grep BUCARDO
docker compose exec db env | grep POSTGRES
```

## Automated Slave Sync Setup

### Complete Process: Master (with data) → Slave (empty)

This is the standard deployment scenario where the master is already running with data and a new slave needs to be brought up to speed.

#### Step 1: Automated Master Data Dump
```bash
# Source your exports first
source /home/cayuse/archive2/temp_corrected_exports.sh
cd archive

# Dump master database (password embedded via PGPASSWORD)
PGPASSWORD="$MASTER_DB_PASS" pg_dump \
  -h "$MASTER_DB_HOST" \
  -p "$MASTER_DB_PORT" \
  -U "$MASTER_DB_USER" \
  -d "$MASTER_DB_NAME" \
  --no-owner --no-privileges \
  > master_full_dump.sql
```

#### Step 2: Automated Slave Data Restore
```bash
# Restore to local slave database (no password prompt)
PGPASSWORD="$POSTGRES_PASSWORD" docker compose exec -T db \
  psql -U postgres -d archive_production < master_full_dump.sql
```

#### Step 3: Verify Data Copy
```bash
# Check counts match
echo -n "Master count: "
PGPASSWORD="$MASTER_DB_PASS" psql \
  -h "$MASTER_DB_HOST" \
  -p "$MASTER_DB_PORT" \
  -U "$MASTER_DB_USER" \
  -d "$MASTER_DB_NAME" \
  -t -c "SELECT COUNT(*) FROM songs;" | tr -d ' '

echo -n "Slave count:  "
docker compose exec -T db psql -U postgres -d archive_production \
  -t -c "SELECT COUNT(*) FROM songs;" | tr -d ' '
```

#### Step 4: Automated Bucardo Setup
```bash
# Add databases to Bucardo (using environment variables)
docker compose exec bucardo bucardo add database local \
  dbname="$MASTER_DB_NAME" host=db port=5432 \
  user=postgres pass="$POSTGRES_PASSWORD"

docker compose exec bucardo bucardo add database master \
  dbname="$MASTER_DB_NAME" host="$MASTER_DB_HOST" port="$MASTER_DB_PORT" \
  user="$MASTER_DB_USER" pass="$MASTER_DB_PASS"

# Add all tables for replication
docker compose exec bucardo bucardo add all tables --db=local,master

# Create and start the sync
docker compose exec bucardo bucardo add sync archive_sync \
  relgroup=default dbs=local,master

docker compose exec bucardo bucardo start archive_sync
```

#### Step 5: Test Replication
```bash
# Test replication with a timestamp-based test record
TEST_TIME=$(date +%s)
PGPASSWORD="$MASTER_DB_PASS" psql \
  -h "$MASTER_DB_HOST" \
  -p "$MASTER_DB_PORT" \
  -U "$MASTER_DB_USER" \
  -d "$MASTER_DB_NAME" \
  -c "INSERT INTO songs (title, created_at, updated_at) VALUES ('replication_test_$TEST_TIME', NOW(), NOW());"

# Wait and check if it appears on slave
sleep 10
docker compose exec -T db psql -U postgres -d archive_production \
  -c "SELECT id, title, created_at FROM songs WHERE title = 'replication_test_$TEST_TIME';"
```

## Notes
- All commands assume you're in the `/home/cayuse/archive2/archive/` directory
- Password prompts should use `password` unless otherwise specified
- The master database at 192.168.1.201 must be accessible via network/VPN
- Bucardo requires both databases to have identical schemas for replication
- Use the `after_deploy_slave.sh` script to automate the complete sync setup process
