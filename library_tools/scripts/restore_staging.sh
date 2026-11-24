#!/usr/bin/env bash
# Rebuild the local staging copy of the archive database from a snapshot.
# Run inside WSL Debian as the postgres OS user:
#   wsl -d Debian -u postgres -- bash /mnt/c/Users/cayuse/ai_stuff/music_archive/scripts/restore_staging.sh <dump file>
# Drops and recreates ONLY the database named archive_staging. Nothing else is touched.
set -euo pipefail

DUMP="${1:?path to a pg_dump -Fc file}"
ROOT=/mnt/c/Users/cayuse/ai_stuff/music_archive
ENVF="$ROOT/.env"
DB=archive_staging
ROLE=archive_staging

if [ ! -f "$ENVF" ]; then
  PW=$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24)
  printf 'POSTGRES_HOST=localhost\nPOSTGRES_PORT=5432\nPOSTGRES_USER=%s\nPOSTGRES_PASSWORD=%s\nPOSTGRES_DB=%s\n' "$ROLE" "$PW" "$DB" > "$ENVF"
fi
PW=$(grep '^POSTGRES_PASSWORD=' "$ENVF" | cut -d= -f2)

psql -v ON_ERROR_STOP=1 -q <<SQL
DO \$\$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$ROLE') THEN
    CREATE ROLE $ROLE LOGIN CREATEDB;
  END IF;
END \$\$;
ALTER ROLE $ROLE PASSWORD '$PW';
DROP DATABASE IF EXISTS $DB;
CREATE DATABASE $DB OWNER $ROLE ENCODING 'UTF8' TEMPLATE template0;
SQL

# Extensions need a superuser; everything else is restored as the staging role.
psql -v ON_ERROR_STOP=1 -q -d "$DB" -c 'CREATE EXTENSION IF NOT EXISTS pgcrypto; CREATE EXTENSION IF NOT EXISTS pg_trgm;'
pg_restore --no-owner --no-privileges --role="$ROLE" -d "$DB" "$DUMP" 2> /tmp/restore_staging.err || true
grep -vE 'already exists|^pg_restore: (warning|error): errors ignored|^Command was|^$' /tmp/restore_staging.err | head -20 || true

psql -At -d "$DB" <<SQL
select 'songs='||count(*) from songs;
select 'albums='||count(*) from albums;
select 'artists='||count(*) from artists;
select 'blobs='||count(*) from active_storage_blobs;
select 'last migration='||max(version) from schema_migrations;
select 'tables='||count(*) from pg_tables where schemaname='public';
select 'not owned by role='||count(*) from pg_tables where schemaname='public' and tableowner <> '$ROLE';
SQL
