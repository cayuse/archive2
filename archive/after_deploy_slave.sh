#!/bin/bash
set -e

# Color functions for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

echo "🔄 Archive Slave Post-Deployment Sync Setup"
echo "============================================="

# Check if running from archive directory and find exports file
if [[ -f "../temp_corrected_exports.sh" ]]; then
    # Running from archive directory - correct location
    EXPORTS_FILE="../temp_corrected_exports.sh"
elif [[ -f "temp_corrected_exports.sh" ]]; then
    # Running from parent directory - also valid
    EXPORTS_FILE="./temp_corrected_exports.sh"
else
    error "Cannot find temp_corrected_exports.sh"
    error "This script should be run from either:"
    error "  /home/cayuse/archive2/archive/ (preferred)"
    error "  /home/cayuse/archive2/"
    exit 1
fi

# Source the exports
info "Loading environment variables from $EXPORTS_FILE..."
source "$EXPORTS_FILE"

# Verify required environment variables
REQUIRED_VARS=(
    "MASTER_DB_HOST" "MASTER_DB_PORT" "MASTER_DB_NAME" "MASTER_DB_USER" "MASTER_DB_PASS"
    "POSTGRES_PASSWORD" "ARCHIVE_ROLE" "REPLICATION_MODE"
)

for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var}" ]]; then
        error "Required environment variable $var is not set"
        exit 1
    fi
done

if [[ "$ARCHIVE_ROLE" != "slave" ]]; then
    error "This script is only for slave deployments. Current ARCHIVE_ROLE: $ARCHIVE_ROLE"
    exit 1
fi

success "Environment variables loaded successfully"
info "Master: $MASTER_DB_HOST:$MASTER_DB_PORT/$MASTER_DB_NAME"
info "Slave: local archive_production database"
info "Replication mode: ${REPLICATION_MODE:-bucardo}"

# Ensure we're in the archive directory
if [[ ! -f "docker-compose.yml" ]]; then
    # We're probably in the parent directory, cd to archive
    if [[ -d "archive" ]]; then
        cd archive
        info "Changed to archive directory"
    else
        error "Cannot find archive directory with docker-compose.yml"
        exit 1
    fi
else
    info "Already in archive directory"
fi

# Check if containers are running
info "Checking container status..."
if ! docker compose ps | grep -q "Up"; then
    error "Docker containers are not running. Please run deployment first:"
    error "  source /home/cayuse/archive2/temp_corrected_exports.sh"
    error "  cd archive && docker compose up -d"
    exit 1
fi

# Wait for containers to be healthy
info "Waiting for containers to be ready..."
for i in {1..30}; do
    if docker compose exec db pg_isready -U postgres >/dev/null 2>&1; then
        success "Database container is ready"
        break
    fi
    if [[ $i -eq 30 ]]; then
        error "Database container failed to become ready"
        exit 1
    fi
    echo "  Waiting for database... ($i/30)"
    sleep 2
done

# Test connectivity to master
info "Testing connectivity to master database..."
if ! PGPASSWORD="$MASTER_DB_PASS" pg_isready -h "$MASTER_DB_HOST" -p "$MASTER_DB_PORT" -U "$MASTER_DB_USER" >/dev/null 2>&1; then
    error "Cannot connect to master database at $MASTER_DB_HOST:$MASTER_DB_PORT"
    error "Please check:"
    error "  1. Master database is running"
    error "  2. Network connectivity (VPN/firewall)"
    error "  3. Master database accepts connections from this IP"
    exit 1
fi
success "Master database connectivity verified"

if [[ "${REPLICATION_MODE:-bucardo}" == "bucardo" ]]; then
  # Check if Bucardo is running (slave-only)
  info "Checking Bucardo status..."
  if ! docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo status >/dev/null 2>&1; then
      error "Bucardo is not running properly. Check logs:"
      error "  docker compose logs bucardo"
      exit 1
  fi
  success "Bucardo is running"
fi

# Step 1: Dump master database with proper constraint handling
info "📥 Dumping master database..."
DUMP_FILE="master_full_dump_$(date +%Y%m%d_%H%M%S).sql"

if ! PGPASSWORD="$MASTER_DB_PASS" pg_dump \
    -h "$MASTER_DB_HOST" \
    -p "$MASTER_DB_PORT" \
    -U "$MASTER_DB_USER" \
    -d "$MASTER_DB_NAME" \
    --no-owner --no-privileges \
    --disable-triggers \
    --data-only \
    --exclude-schema=bucardo \
    > "$DUMP_FILE"; then
    error "Failed to dump master database"
    exit 1
fi

DUMP_SIZE=$(du -h "$DUMP_FILE" | cut -f1)
success "Master database dumped to $DUMP_FILE (Size: $DUMP_SIZE)"

# Step 2: Get record counts before restore
info "📊 Checking initial record counts..."
MASTER_COUNT=$(PGPASSWORD="$MASTER_DB_PASS" psql \
    -h "$MASTER_DB_HOST" \
    -p "$MASTER_DB_PORT" \
    -U "$MASTER_DB_USER" \
    -d "$MASTER_DB_NAME" \
    -t -c "SELECT COUNT(*) FROM songs;" 2>/dev/null | tr -d ' ' || echo "0")

SLAVE_COUNT_BEFORE=$(docker compose exec -T db psql -U postgres -d archive_production \
    -t -c "SELECT COUNT(*) FROM songs;" 2>/dev/null | tr -d ' ' || echo "0")

info "Master has $MASTER_COUNT songs"
info "Slave currently has $SLAVE_COUNT_BEFORE songs"

# Step 3: Restore to slave database with constraint handling
info "📤 Restoring data to slave database..."

# Clear existing data first if this is a re-run
if [[ "$SLAVE_COUNT_BEFORE" -gt 0 ]]; then
    info "  Clearing existing data for clean restore..."
    docker compose exec -T db psql -U postgres -d archive_production -c "
        TRUNCATE TABLE playlists_songs, albums_genres, artists_genres CASCADE;
        TRUNCATE TABLE songs, playlists, active_storage_attachments, active_storage_variant_records CASCADE;
        TRUNCATE TABLE albums, active_storage_blobs, system_settings, themes, theme_assets CASCADE;
        TRUNCATE TABLE artists, genres, users CASCADE;
    " 2>/dev/null || warning "Could not clear existing data"
fi

info "  Disabling triggers and foreign key checks..."
if ! docker compose exec -T db psql -U postgres -d archive_production -c "SET session_replication_role = replica;" || \
   ! docker compose exec -T db psql -U postgres -d archive_production < "$DUMP_FILE" || \
   ! docker compose exec -T db psql -U postgres -d archive_production -c "SET session_replication_role = DEFAULT;"; then
    error "Failed to restore data to slave database"
    # Try to re-enable constraints even on failure
    docker compose exec -T db psql -U postgres -d archive_production -c "SET session_replication_role = DEFAULT;" 2>/dev/null || true
    exit 1
fi
success "Data restored to slave database"

# Step 4: Verify data copy
info "✅ Verifying data copy..."
SLAVE_COUNT_AFTER=$(docker compose exec -T db psql -U postgres -d archive_production \
    -t -c "SELECT COUNT(*) FROM songs;" | tr -d ' ')

if [[ "$MASTER_COUNT" != "$SLAVE_COUNT_AFTER" ]]; then
    warning "Record count mismatch!"
    warning "  Master: $MASTER_COUNT songs"
    warning "  Slave:  $SLAVE_COUNT_AFTER songs"
    warning "Continuing with Bucardo setup, but investigate the discrepancy"
else
    success "Data copy verified: $MASTER_COUNT songs on both master and slave"
fi

if [[ "${REPLICATION_MODE:-bucardo}" == "bucardo" ]]; then
  # Step 5: Setup Bucardo replication
  info "🔧 Setting up Bucardo replication..."

# Add local database
info "Adding local database to Bucardo..."
if ! docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo add database local \
    dbname="$MASTER_DB_NAME" host=db port=5432 \
    user=postgres pass="$POSTGRES_PASSWORD"; then
    warning "Local database may already exist in Bucardo"
fi

# Add master database
info "Adding master database to Bucardo..."
if ! docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo add database master \
    dbname="$MASTER_DB_NAME" host="$MASTER_DB_HOST" port="$MASTER_DB_PORT" \
    user="$MASTER_DB_USER" pass="$MASTER_DB_PASS"; then
    warning "Master database may already exist in Bucardo"
fi

# Add individual tables in dependency order
info "Adding core tables for replication..."
# First, add tables with no dependencies
docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo add table users --db=local,master 2>/dev/null || warning "Users table may already exist"
docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo add table genres --db=local,master 2>/dev/null || warning "Genres table may already exist"
docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo add table artists --db=local,master 2>/dev/null || warning "Artists table may already exist"

# Then tables that depend on artists
docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo add table albums --db=local,master 2>/dev/null || warning "Albums table may already exist"

# Then relationship tables
docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo add table artists_genres --db=local,master 2>/dev/null || warning "Artists_genres table may already exist"
docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo add table albums_genres --db=local,master 2>/dev/null || warning "Albums_genres table may already exist"

# Finally, songs table (depends on users, genres, artists, albums)
docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo add table songs --db=local,master 2>/dev/null || warning "Songs table may already exist"

# Add playlists and related tables
docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo add table playlists --db=local,master 2>/dev/null || warning "Playlists table may already exist"
docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo add table playlists_songs --db=local,master 2>/dev/null || warning "Playlists_songs table may already exist"

# Add system tables
docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo add table system_settings --db=local,master 2>/dev/null || warning "System_settings table may already exist"
docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo add table themes --db=local,master 2>/dev/null || warning "Themes table may already exist"

# Add Active Storage tables (including the missing ones)
docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo add table active_storage_blobs --db=local,master 2>/dev/null || warning "Active_storage_blobs table may already exist"
docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo add table active_storage_attachments --db=local,master 2>/dev/null || warning "Active_storage_attachments table may already exist"
docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo add table active_storage_variant_records --db=local,master 2>/dev/null || warning "Active_storage_variant_records table may already exist"

# Add theme-related tables
docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo add table theme_assets --db=local,master 2>/dev/null || warning "Theme_assets table may already exist"

# Add all tables to the default relgroup
info "Adding tables to relgroup..."
docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo add relgroup default \
    users genres artists albums artists_genres albums_genres songs playlists playlists_songs \
    system_settings themes active_storage_blobs active_storage_attachments active_storage_variant_records theme_assets 2>/dev/null || warning "Relgroup may already be configured"

# Create polling-based sync (master->local for slave)
info "Creating Bucardo sync with polling-based replication (master->local)..."
# Remove existing sync if it exists
docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo remove sync archive_sync 2>/dev/null || warning "Sync may not exist yet"

# Create sync with polling configuration: master=source, local=target  
# Create standard sync (polling will be handled by cron kicks)
if ! docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo add sync archive_sync \
    relgroup=default dbs=master:source,local:target; then
    error "Failed to create sync with correct direction"
    exit 1
fi

# Configure the sync for polling behavior (no triggers needed)
info "Configuring polling-based replication settings..."
# Disable one-time copy so it runs continuously  
docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo update sync archive_sync onetimecopy=false 2>/dev/null || warning "Could not set onetimecopy"
# Keep the sync alive
docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo update sync archive_sync stayalive=true 2>/dev/null || warning "Could not set stayalive"
# Disable autokick (we'll kick manually via cron)
docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo update sync archive_sync autokick=false 2>/dev/null || warning "Could not set autokick"

# Start sync
info "Starting Bucardo sync..."
if ! docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo start archive_sync; then
    warning "Sync may already be running"
fi

# Set up cron job for periodic sync kicks
info "Setting up periodic sync schedule (every $BUCARDO_SYNC_FREQUENCY minutes)..."
# Create a cron job inside the bucardo container to kick the sync at specified frequency
docker compose exec bucardo bash -c "echo '*/$BUCARDO_SYNC_FREQUENCY * * * * /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo kick archive_sync > /var/log/bucardo/cron.log 2>&1' | crontab -" 2>/dev/null || warning "Could not set up cron job"

# Start cron service in the container
docker compose exec bucardo service cron start 2>/dev/null || warning "Could not start cron service"

  success "Bucardo replication setup complete with $BUCARDO_SYNC_FREQUENCY-minute polling"

# Step 6: Test replication
  info "🧪 Testing replication (master -> slave direction)..."
TEST_TIME=$(date +%s)
TEST_TITLE="replication_test_$TEST_TIME"

# Verify sync direction first
info "Verifying sync direction..."
SYNC_INFO=$(docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo list syncs | grep archive_sync || echo "")
if [[ "$SYNC_INFO" == *"master:source"* && "$SYNC_INFO" == *"local:target"* ]]; then
    success "✅ Sync direction is correct: master->local"
elif [[ "$SYNC_INFO" == *"local:source"* && "$SYNC_INFO" == *"master:target"* ]]; then
    error "❌ Sync direction is WRONG: local->master (should be master->local)"
    error "The sync needs to be recreated with correct direction"
    exit 1
else
    warning "⚠️  Could not determine sync direction from: $SYNC_INFO"
fi

info "Adding test record to master: $TEST_TITLE"
if ! PGPASSWORD="$MASTER_DB_PASS" psql \
    -h "$MASTER_DB_HOST" \
    -p "$MASTER_DB_PORT" \
    -U "$MASTER_DB_USER" \
    -d "$MASTER_DB_NAME" \
    -c "INSERT INTO songs (title, created_at, updated_at) VALUES ('$TEST_TITLE', NOW(), NOW());"; then
    error "Failed to insert test record on master"
    exit 1
fi

info "Manually kicking sync to test polling-based replication..."
docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo kick archive_sync

info "Waiting 30 seconds for polling-based sync to complete..."
sleep 30

info "Checking for test record on slave..."
FOUND_COUNT=$(docker compose exec -T db psql -U postgres -d archive_production \
    -t -c "SELECT COUNT(*) FROM songs WHERE title = '$TEST_TITLE';" | tr -d ' ')

if [[ "$FOUND_COUNT" == "1" ]]; then
    success "✨ Replication test PASSED! Test record found on slave"
    docker compose exec -T db psql -U postgres -d archive_production \
        -c "SELECT 'Test record:' as status, id, title, created_at FROM songs WHERE title = '$TEST_TITLE';"
    
    # Clean up test record from master (it will replicate deletion too)
    info "Cleaning up test record from master..."
    PGPASSWORD="$MASTER_DB_PASS" psql \
        -h "$MASTER_DB_HOST" \
        -p "$MASTER_DB_PORT" \
        -U "$MASTER_DB_USER" \
        -d "$MASTER_DB_NAME" \
        -c "DELETE FROM songs WHERE title = '$TEST_TITLE';" 2>/dev/null || warning "Could not clean up test record"
else
    error "❌ Replication test FAILED! Test record not found on slave"
    error "Expected 1 record, found $FOUND_COUNT"
    info "Check Bucardo logs: docker compose logs bucardo"
    info "Check Bucardo status: docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo status archive_sync"
  fi
else
  # Step 5: Setup logical replication subscription on slave
  info "🔧 Setting up PostgreSQL logical replication (subscription on slave)..."

  # Ensure logical replication settings are visible/healthy (no hard fail here)
  docker compose exec -T db psql -U postgres -c "SHOW wal_level;" >/dev/null 2>&1 || true

  # Create subscription idempotently
  info "Creating subscription ${SUB_NAME:-sub_archive} (copy_data=false)..."
  docker compose exec -T db psql -U postgres -d archive_production -c "DROP SUBSCRIPTION IF EXISTS ${SUB_NAME:-sub_archive};" >/dev/null 2>&1 || true
  if ! docker compose exec -T db psql -U postgres -d archive_production -c "CREATE SUBSCRIPTION ${SUB_NAME:-sub_archive} CONNECTION 'host=${MASTER_DB_HOST} port=${MASTER_DB_PORT} dbname=${MASTER_DB_NAME} user=${REPL_USER:-archive_replicator} password=${REPL_PASS:-change-me}' PUBLICATION ${PUB_NAME:-pub_archive} WITH (copy_data=false, create_slot=true, slot_name='${SUB_SLOT_NAME:-sub_archive_slot}');"; then
      error "Failed to create subscription. Verify master publication, user, network, and credentials."
      exit 1
  fi

  success "Subscription ${SUB_NAME:-sub_archive} created"

  # Quick replication smoke test
  info "🧪 Testing logical replication (master -> slave)..."
  TEST_TIME=$(date +%s)
  TEST_TITLE="lr_test_$TEST_TIME"
  if ! PGPASSWORD="$MASTER_DB_PASS" psql -h "$MASTER_DB_HOST" -p "$MASTER_DB_PORT" -U "$MASTER_DB_USER" -d "$MASTER_DB_NAME" -c "INSERT INTO songs (id, title, created_at, updated_at) VALUES (gen_random_uuid(), '$TEST_TITLE', NOW(), NOW());"; then
      warning "Could not insert test record on master; skipping test"
  else
      sleep 5
      FOUND_COUNT=$(docker compose exec -T db psql -U postgres -d archive_production -t -c "SELECT COUNT(*) FROM songs WHERE title = '$TEST_TITLE';" | tr -d ' ')
      if [[ "$FOUND_COUNT" == "1" ]]; then
          success "✨ Logical replication test PASSED!"
      else
          warning "⚠️  Logical replication test did not find record yet; check pg_stat_subscription"
      fi
  fi
fi
fi

# Final status and verification
echo ""
info "🔍 Final verification..."
FINAL_SONGS=$(docker compose exec -T db psql -U postgres -d archive_production -t -c "SELECT COUNT(*) FROM songs;" | tr -d ' ')
FINAL_ARTISTS=$(docker compose exec -T db psql -U postgres -d archive_production -t -c "SELECT COUNT(*) FROM artists;" | tr -d ' ')
FINAL_ALBUMS=$(docker compose exec -T db psql -U postgres -d archive_production -t -c "SELECT COUNT(*) FROM albums;" | tr -d ' ')

echo ""
success "🎉 Slave sync setup completed!"
info "📋 Summary:"
info "  - Master dump: $DUMP_FILE ($DUMP_SIZE)"
info "  - Songs synced: $FINAL_SONGS (Master: $MASTER_COUNT)"
info "  - Artists synced: $FINAL_ARTISTS"
info "  - Albums synced: $FINAL_ALBUMS"
info "  - Replication: Active"

if [[ "$FINAL_SONGS" == "$MASTER_COUNT" ]] && [[ "$FINAL_SONGS" != "0" ]]; then
    success "✅ Data sync verification PASSED!"
else
    warning "⚠️  Data sync verification shows discrepancy - check logs"
fi

echo ""
info "⚙️  Replication Settings:"
if [[ "${REPLICATION_MODE:-bucardo}" == "bucardo" ]]; then
  info "  - Mode: Bucardo (polling via cron)"
  info "  - Direction: master ($MASTER_DB_HOST) -> slave (local)"
  info "  - Interval: Every $BUCARDO_SYNC_FREQUENCY minute(s)"
else
  info "  - Mode: PostgreSQL logical replication"
  info "  - Direction: master ($MASTER_DB_HOST) -> slave (subscription ${SUB_NAME:-sub_archive})"
  info "  - Interval: near real-time (streaming)"
fi
echo ""
info "📚 Useful commands:"
info "  Check sync status: docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo status archive_sync"
info "  View Bucardo logs: docker compose logs bucardo"
info "  Monitor replication: watch 'docker compose exec -T db psql -U postgres -d archive_production -t -c \"SELECT COUNT(*) FROM songs;\"'"
info "  List all synced tables: docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo list tables"
info "  Manual sync trigger: docker compose exec bucardo /usr/bin/bucardo-original --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo kick archive_sync"
info ""
info "🗑️  Cleanup:"
info "  Remove dump file: rm $DUMP_FILE"

# Cleanup dump file option
echo ""
read -p "Remove the dump file $DUMP_FILE? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm "$DUMP_FILE"
    info "Dump file removed"
fi

success "After-deployment setup complete!"
