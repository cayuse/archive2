#!/usr/bin/env bash
# psql against the MusicBrainz mirror on bigballs (read-only use).
set -euo pipefail
set -a; . /mnt/c/Users/cayuse/ai_stuff/music_archive/.env; set +a
PGPASSWORD="$MB_PASSWORD" PGOPTIONS="-c default_transaction_read_only=on -c search_path=musicbrainz,public" exec psql -h "$MB_HOST" -p "$MB_PORT" -U "$MB_USER" -d "$MB_DB" -v ON_ERROR_STOP=1 "$@"
