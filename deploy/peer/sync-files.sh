#!/bin/sh
# Pull new music files from other peers into this peer's storage (docs/PEERS.md, "Files").
#
#   archive-sync-files <storage dir> <sync account@host> [...]
#   archive-sync-files <storage dir>                      (peers from /etc/archive/file-peers)
#
# Files in Active Storage are written once under a random name and never changed, so pulling with
# --ignore-existing from every peer converges every peer on the union, and nothing is ever deleted
# or overwritten. The other side's key only allows `rrsync -ro <its storage>`: this can read their
# files and do nothing else. Run it as the account that owns the storage (uid 1000, the app
# container's user) so the files land with the right owner. Safe to run often: one at a time
# (flock), resumes partial files, DRY_RUN=1 lists without copying, BWLIMIT=<KB/s> throttles.
set -eu
STORAGE=${1:?usage: archive-sync-files <storage dir> [sync-account@host ...]}
shift
[ "$#" -gt 0 ] || set -- $(grep -v '^\s*#' /etc/archive/file-peers 2>/dev/null || true)
[ "$#" -gt 0 ] || { echo "no peers to pull from" >&2; exit 0; }
KEY=${ARCHIVE_SYNC_KEY:-$HOME/.ssh/archive_sync_ed25519}
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/archive-sync-files.lock"
flock -n 9 || { echo "a sync is already running" >&2; exit 0; }
status=0
for peer in "$@"; do
  echo "$(date -u +%FT%TZ) pulling from $peer"
  rsync -a --ignore-existing --partial-dir=.rsync-partial --exclude=.rsync-partial/ --chmod=D755,F644 \
    --timeout=600 --info=stats1 ${BWLIMIT:+--bwlimit=$BWLIMIT} ${DRY_RUN:+--dry-run} \
    -e "ssh -i $KEY -o IdentitiesOnly=yes -o BatchMode=yes -o ServerAliveInterval=30 -o StrictHostKeyChecking=accept-new" \
    "$peer:/" "$STORAGE/" || { echo "pull from $peer failed (exit $?)" >&2; status=1; }
done
exit $status
