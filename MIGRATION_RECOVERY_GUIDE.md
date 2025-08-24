# Migration Recovery Guide

## Overview

This guide covers how to recover from the migration issues caused by renaming migration files. The problem is that renaming migrations breaks the migration history on production servers, making it impossible to run new migrations.

## The Problem

When migration files are renamed:
- **Production servers** think they've already run migrations with the old names
- **New filenames** are treated as completely new migrations
- **This can cause data loss** or duplicate table creation
- **Migration history becomes inconsistent** between environments

## Recovery Options

### Option 1: Full Database Backup & Restore (Recommended)

This approach completely resets the migration state and restores your data.

#### Step 1: Backup Your Current Data

```bash
# Navigate to archive directory
cd archive

# Create a full database backup (schema + data)
docker compose exec db pg_dump -U postgres archive_production > archive_full_backup.sql

# Alternative: Backup just the data (no schema)
docker compose exec db pg_dump -U postgres --data-only archive_production > archive_data_only.sql

# Alternative: Backup just the schema (no data)
docker compose exec db pg_dump -U postgres --schema-only archive_production > archive_schema_only.sql

# Backup specific important tables
docker compose exec db pg_dump -U postgres \
  --table=songs \
  --table=artists \
  --table=albums \
  --table=genres \
  --table=playlists \
  --table=users \
  archive_production > music_data_backup.sql
```

#### Step 2: Reset the Database

```bash
# Stop the archive application
docker compose stop archive

# Drop and recreate the database
docker compose exec db psql -U postgres -c "DROP DATABASE archive_production;"
docker compose exec db psql -U postgres -c "CREATE DATABASE archive_production;"

# Verify the database is empty
docker compose exec db psql -U postgres -c "\dt" archive_production
```

#### Step 3: Run Migrations from Scratch

```bash
# Start the archive application
docker compose start archive

# Wait for it to be ready, then run migrations
docker compose exec archive rails db:migrate

# Verify all tables were created
docker compose exec archive rails db:migrate:status
```

#### Step 4: Restore Your Data

```bash
# Restore the full backup (recommended)
docker compose exec -T db psql -U postgres archive_production < archive_full_backup.sql

# Or restore just the data
docker compose exec -T db psql -U postgres archive_production < archive_data_only.sql

# Or restore specific tables
docker compose exec -T db psql -U postgres archive_production < music_data_backup.sql
```

#### Step 5: Verify Restoration

```bash
# Check that your data is back
docker compose exec db psql -U postgres -c "SELECT COUNT(*) FROM songs;" archive_production
docker compose exec db psql -U postgres -c "SELECT COUNT(*) FROM users;" archive_production

# Restart the application
docker compose restart archive
```

### Option 2: In-Place Migration Fix (Advanced)

This approach tries to fix the existing migrations without losing data.

#### Step 1: Restore Original Migration Names

```bash
# Rename migrations back to their original names
mv db/migrate/20250823000001_create_sync_status_tracking.rb db/migrate/20250121000001_create_sync_status_tracking.rb
mv db/migrate/20250823000002_create_system_settings.rb db/migrate/20250715180254_create_system_settings.rb
mv db/migrate/20250823000003_add_archive_sync_settings.rb db/migrate/20250719192041_add_archive_sync_settings.rb
mv db/migrate/20250823000004_create_sync_changes.rb db/migrate/20250719202752_create_sync_changes.rb
mv db/migrate/20250823000005_create_slave_keys.rb db/migrate/20250719202803_create_slave_keys.rb
mv db/migrate/20250823000006_create_jukebox_keys.rb db/migrate/20250719202812_create_jukebox_keys.rb
mv db/migrate/20250823000007_create_conflict_logs.rb db/migrate/20250719205308_create_conflict_logs.rb
```

#### Step 2: Fix Migration Dependencies

The migrations need to be fixed to handle the `system_settings` table dependency issue.

#### Step 3: Try to Migrate

```bash
# Attempt to run migrations
docker compose exec archive rails db:migrate

# If it fails, you'll need to go with Option 1
```

### Option 3: Selective Data Migration (Most Complex)

This approach migrates data table by table.

#### Step 1: Backup Individual Tables

```bash
# Backup each table separately
docker compose exec db pg_dump -U postgres --table=songs archive_production > songs_backup.sql
docker compose exec db pg_dump -U postgres --table=artists archive_production > artists_backup.sql
docker compose exec db pg_dump -U postgres --table=albums archive_production > albums_backup.sql
docker compose exec db pg_dump -U postgres --table=genres archive_production > genres_backup.sql
docker compose exec db pg_dump -U postgres --table=playlists archive_production > playlists_backup.sql
docker compose exec db pg_dump -U postgres --table=users archive_production > users_backup.sql
```

#### Step 2: Restore After Migration

```bash
# Restore each table after migrations complete
docker compose exec -T db psql -U postgres archive_production < songs_backup.sql
docker compose exec -T db psql -U postgres archive_production < artists_backup.sql
docker compose exec -T db psql -U postgres archive_production < albums_backup.sql
docker compose exec -T db psql -U postgres archive_production < genres_backup.sql
docker compose exec -T db psql -U postgres archive_production < playlists_backup.sql
docker compose exec -T db psql -U postgres archive_production < users_backup.sql
```

## PostgreSQL Commands Reference

### Backup Commands

```bash
# Full database backup
pg_dump -U postgres database_name > backup.sql

# Data only (no schema)
pg_dump -U postgres --data-only database_name > data_backup.sql

# Schema only (no data)
pg_dump -U postgres --schema-only database_name > schema_backup.sql

# Specific tables
pg_dump -U postgres --table=table1 --table=table2 database_name > tables_backup.sql

# Compressed backup
pg_dump -U postgres database_name | gzip > backup.sql.gz
```

### Restore Commands

```bash
# Restore from file
psql -U postgres database_name < backup.sql

# Restore compressed backup
gunzip -c backup.sql.gz | psql -U postgres database_name

# Restore specific tables
psql -U postgres database_name < tables_backup.sql
```

### Database Management

```bash
# List databases
psql -U postgres -c "\l"

# Connect to database
psql -U postgres database_name

# List tables
\dt

# Count rows in table
SELECT COUNT(*) FROM table_name;

# Drop database
DROP DATABASE database_name;

# Create database
CREATE DATABASE database_name;
```

## Safety Checklist

Before proceeding with any recovery option:

- [ ] **Verify backup size** - Ensure backup files are not empty
- [ ] **Test backup integrity** - Try to restore to a test database
- [ ] **Document current state** - Note any custom configurations
- [ ] **Stop applications** - Prevent data changes during recovery
- [ ] **Have rollback plan** - Know how to restore from backup if needed

## Recovery Time Estimates

- **Option 1 (Full backup/restore)**: 30-60 minutes
- **Option 2 (In-place fix)**: 15-30 minutes (if successful)
- **Option 3 (Selective migration)**: 60-120 minutes

## When to Use Each Option

### Use Option 1 (Full backup/restore) when:
- You have a recent backup
- You want the safest approach
- You have time for a complete reset
- You want to ensure clean migration state

### Use Option 2 (In-place fix) when:
- You're comfortable with migration debugging
- You want to minimize downtime
- You have a small amount of data
- You want to preserve exact migration history

### Use Option 3 (Selective migration) when:
- You have very large datasets
- You need to preserve specific data
- You have time for careful table-by-table work
- You want maximum control over the process

## Post-Recovery Verification

After recovery, verify:

1. **All tables exist** and have correct structure
2. **Data is restored** with correct row counts
3. **Migrations show as complete** in `db:migrate:status`
4. **Application starts** without errors
5. **Sync functionality works** (if that was the goal)

## Prevention for Future

To avoid this issue in the future:

1. **Never rename migration files** after they've been deployed
2. **Test migrations** in development before production
3. **Use proper migration timestamps** (chronological order)
4. **Keep backups** before running migrations
5. **Use migration rollbacks** instead of file renames

## Emergency Contacts

If you need help during recovery:

1. **Check application logs**: `docker compose logs archive`
2. **Check database logs**: `docker compose logs db`
3. **Verify migration status**: `docker compose exec archive rails db:migrate:status`
4. **Check table existence**: `docker compose exec db psql -U postgres -c "\dt" archive_production`

---

**Remember**: Always test recovery procedures on a copy of your data first, and never attempt recovery on production without a verified backup.
