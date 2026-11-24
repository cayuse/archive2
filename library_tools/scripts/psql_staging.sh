#!/usr/bin/env bash
# psql against the local staging database, as the staging role over TCP.
# Usage inside WSL:  bash psql_staging.sh -c "select 1"     or     bash psql_staging.sh -f file.sql
set -euo pipefail
set -a; . /mnt/c/Users/cayuse/ai_stuff/music_archive/.env; set +a
PGPASSWORD="$POSTGRES_PASSWORD" exec psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 "$@"
