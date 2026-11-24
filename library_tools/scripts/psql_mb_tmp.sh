#!/usr/bin/env bash
# Like psql_mb.sh but allows session-only temp tables (nothing persistent is written to the mirror).
set -euo pipefail
set -a; . /mnt/c/Users/cayuse/ai_stuff/music_archive/.env; set +a
PGPASSWORD="$MB_PASSWORD" PGOPTIONS="-c search_path=pg_temp,musicbrainz,public -c statement_timeout=300000" exec psql -h "$MB_HOST" -p "$MB_PORT" -U "$MB_USER" -d "$MB_DB" -v ON_ERROR_STOP=1 "$@"
