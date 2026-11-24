#!/usr/bin/env bash
# Copy the archive's audio blobs from bigballs to this PC (read-only on bigballs; resumable).
# Only the blobs that belong to songs (work/songs.tsv) are copied, laid out as XX/YY/<key> like the source.
# Usage (inside WSL): bash mirror_audio.sh
set -euo pipefail
ROOT=/mnt/c/Users/cayuse/ai_stuff/music_archive
DEST=$ROOT/audio
mkdir -p "$DEST"
awk -F'\t' '{k=$2; print substr(k,1,2) "/" substr(k,3,2) "/" k}' "$ROOT/work/songs.tsv" > "$ROOT/work/blob_paths.txt"
exec rsync -a --partial --inplace --no-perms --no-owner --no-group --files-from="$ROOT/work/blob_paths.txt" \
  --info=progress2,stats1 -e "ssh -o BatchMode=yes -o Compression=no" \
  cayuse@192.168.17.109:/datatank/archive/psql_storage/ "$DEST/"
