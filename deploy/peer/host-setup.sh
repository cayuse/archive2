#!/bin/sh
# Prepare a host to be (or to sync with) an archive peer. Run as root, once; safe to run again.
# docs/PEERS.md, "1. Hosts". Everything is set through the environment:
#
#   STORAGE_DIR     the music files (default $ARCHIVE_ROOT/storage; bigballs: /datatank/archive/psql_storage)
#   ARCHIVE_ROOT    a peer's data: storage/ intake/ postgres/ redis/  (default /srv/archive)
#   DATA_UID        owner of the files: the app container runs as uid 1000 (default 1000)
#   DEPLOY_USER     the account Kamal connects as, in the docker group (default archive)
#   DEPLOY_KEY      public key of the machine that deploys with Kamal (added to DEPLOY_USER)
#   SYNC_USER       the account other peers pull files through, read-only (default archive-sync)
#   PEER_KEYS       file of the other peers' puller public keys, one per line (added to SYNC_USER)
#   FILE_PEERS      sync accounts to pull files from, e.g. "archive-sync@10.66.0.2" (space separated)
#   SKIP_PEER_DIRS  1 on a host that only syncs files (bigballs): no postgres/redis/intake dirs
set -eu
[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
ARCHIVE_ROOT=${ARCHIVE_ROOT:-/srv/archive}
STORAGE_DIR=${STORAGE_DIR:-$ARCHIVE_ROOT/storage}
DATA_UID=${DATA_UID:-1000}
DEPLOY_USER=${DEPLOY_USER:-archive}
SYNC_USER=${SYNC_USER:-archive-sync}
HERE=$(cd "$(dirname "$0")" && pwd)
say() { echo "host-setup: $*"; }

for c in rsync ssh-keygen useradd flock; do command -v $c >/dev/null || { echo "missing $c (apt install rsync openssh-client passwd util-linux)" >&2; exit 1; }; done
getent group docker >/dev/null || { echo "no docker group: install Docker first" >&2; exit 1; }
RRSYNC=$(command -v rrsync || true)
if [ -z "$RRSYNC" ]; then
  for f in /usr/share/doc/rsync/scripts/rrsync /usr/share/doc/rsync/scripts/rrsync.gz; do
    [ -f "$f" ] || continue
    case $f in *.gz) gunzip -c "$f" > /usr/local/bin/rrsync ;; *) cp "$f" /usr/local/bin/rrsync ;; esac
    chmod 755 /usr/local/bin/rrsync; RRSYNC=/usr/local/bin/rrsync; break
  done
fi
[ -n "$RRSYNC" ] || { echo "rrsync not found (comes with rsync 3.2.4+)" >&2; exit 1; }
# rrsync is a Python script: without python3 every pull fails with "rrsync: not found"
interp=$(head -1 "$RRSYNC" | sed -n 's|^#! *\([^ ]*\).*|\1|p')
case "$interp" in */env) interp=$(head -1 "$RRSYNC" | awk '{print $2}');; esac
[ -z "$interp" ] || command -v "$interp" >/dev/null || [ -x "$interp" ] || { echo "rrsync needs $interp (apt install python3)" >&2; exit 1; }

# 1. The account that owns the music files: whoever has DATA_UID, or a new archive-data.
DATA_USER=$(getent passwd "$DATA_UID" | cut -d: -f1 || true)
if [ -z "$DATA_USER" ]; then
  useradd --system --uid "$DATA_UID" --user-group --create-home --home-dir /var/lib/archive-data --shell /bin/sh archive-data
  DATA_USER=archive-data; say "created $DATA_USER (uid $DATA_UID) to own the files"
else
  say "files are owned by $DATA_USER (uid $DATA_UID)"
fi
DATA_HOME=$(getent passwd "$DATA_USER" | cut -d: -f6)

# 2. The deploy account (Kamal connects as it; docker group = it can run containers).
if ! id "$DEPLOY_USER" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "$DEPLOY_USER"; say "created $DEPLOY_USER"
fi
usermod -aG docker "$DEPLOY_USER"
if [ -n "${DEPLOY_KEY:-}" ]; then
  d=$(getent passwd "$DEPLOY_USER" | cut -d: -f6)/.ssh; install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$d"
  touch "$d/authorized_keys"; grep -qF "$DEPLOY_KEY" "$d/authorized_keys" || echo "$DEPLOY_KEY" >> "$d/authorized_keys"
  chown "$DEPLOY_USER:$DEPLOY_USER" "$d/authorized_keys"; chmod 600 "$d/authorized_keys"
fi

# 3. Directories.
install -d -m 755 -o "$DATA_UID" -g "$(id -g "$DATA_USER")" "$STORAGE_DIR"
if [ "${SKIP_PEER_DIRS:-0}" != 1 ]; then
  install -d -m 755 -o "$DATA_UID" -g "$(id -g "$DATA_USER")" "$ARCHIVE_ROOT/intake"
  install -d -m 700 "$ARCHIVE_ROOT/postgres" "$ARCHIVE_ROOT/redis"   # the containers take ownership
fi

# 4. The read-only sync account other peers pull through.
if ! id "$SYNC_USER" >/dev/null 2>&1; then
  useradd --system --create-home --home-dir "/var/lib/$SYNC_USER" --shell /bin/sh "$SYNC_USER"
  passwd -l "$SYNC_USER" >/dev/null; say "created $SYNC_USER"
fi
SYNC_HOME=$(getent passwd "$SYNC_USER" | cut -d: -f6)
install -d -m 700 -o "$SYNC_USER" -g "$SYNC_USER" "$SYNC_HOME/.ssh"
ak="$SYNC_HOME/.ssh/authorized_keys"; touch "$ak"
if [ -n "${PEER_KEYS:-}" ]; then
  grep -v '^\s*#' "$PEER_KEYS" | grep . | while read -r key; do
    grep -qF "$key" "$ak" || echo "command=\"$RRSYNC -ro $STORAGE_DIR\",restrict $key" >> "$ak"
  done
fi
chown "$SYNC_USER:$SYNC_USER" "$ak"; chmod 600 "$ak"
su -s /bin/sh "$SYNC_USER" -c "test -r '$STORAGE_DIR' -a -x '$STORAGE_DIR'" \
  || say "WARNING: $SYNC_USER cannot read $STORAGE_DIR (a parent directory is closed?): other peers will not get files"

# 5. Pulling files from the other peers: the data owner's key, the script, a cron job.
install -d -m 700 -o "$DATA_USER" -g "$(id -g "$DATA_USER")" "$DATA_HOME/.ssh"
[ -f "$DATA_HOME/.ssh/archive_sync_ed25519" ] || su -s /bin/sh "$DATA_USER" -c \
  "ssh-keygen -q -t ed25519 -N '' -C 'archive-sync $(hostname)' -f '$DATA_HOME/.ssh/archive_sync_ed25519'"
install -m 755 "$HERE/sync-files.sh" /usr/local/bin/archive-sync-files
install -d -m 755 /etc/archive
[ -f /etc/archive/file-peers ] || echo "# sync accounts to pull music files from, one per line: archive-sync@<peer address>" > /etc/archive/file-peers
for p in ${FILE_PEERS:-}; do grep -qxF "$p" /etc/archive/file-peers || echo "$p" >> /etc/archive/file-peers; done
cat > /etc/cron.d/archive-sync-files <<CRON
# Pull new music files from the other archive peers (docs/PEERS.md). Peers: /etc/archive/file-peers
*/5 * * * * $DATA_USER /usr/local/bin/archive-sync-files $STORAGE_DIR >> /var/log/archive-sync-files.log 2>&1
CRON
touch /var/log/archive-sync-files.log; chown "$DATA_USER" /var/log/archive-sync-files.log

say "done. Give the other peers this host's puller key (they add it to $SYNC_USER via PEER_KEYS):"
cat "$DATA_HOME/.ssh/archive_sync_ed25519.pub"
