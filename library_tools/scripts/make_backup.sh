#!/usr/bin/env bash
# Dump the repaired STAGING database and ship it, plus the replay data, to bigballs.
# Runs inside WSL:  bash make_backup.sh
set -euo pipefail
ROOT=/mnt/c/Users/cayuse/ai_stuff/music_archive
DEST=cayuse@192.168.17.109
DIR=/datatank/downloads/archive_repaired_backup
STAMP=$(date +%Y%m%d-%H%M)
set -a; . "$ROOT/.env"; set +a

OUT=/tmp/archive_repaired_$STAMP.dump
echo "== dumping staging"
PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -Fc -Z 6 --no-owner --no-acl --no-subscriptions -f "$OUT"
ls -la "$OUT"
pg_restore -l "$OUT" | grep -c "TABLE DATA" | sed 's/^/tables with data: /'

echo "== shipping"
ssh -o BatchMode=yes $DEST "mkdir -p $DIR"
scp -q -o BatchMode=yes "$OUT" "$DEST:$DIR/"
( cd "$ROOT/work" && tar czf - tags.jsonl mb/lookup_artist.tsv mb/lookup_release.tsv mb/lookup_recording.tsv \
    audio/out/features.tsv audio/out/neighbors.tsv audio/out/embeddings.tsv audio/out/genre_affinity.tsv audio/errors.jsonl ) \
  | ssh -o BatchMode=yes $DEST "cat > $DIR/replay_data_$STAMP.tar.gz"
scp -q -o BatchMode=yes "$ROOT/work/BACKUP_README.md" "$DEST:$DIR/README.md"
ssh -o BatchMode=yes $DEST "cd $DIR && sha256sum *.dump *.tar.gz > SHA256SUMS && ls -la"
rm -f "$OUT"
echo "STAMP=$STAMP"
