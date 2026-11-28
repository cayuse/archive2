#!/usr/bin/env bash
# Runs scan.py in the audit container on this machine. Extra arguments go to scan.py.
#   AUDIT_DIR      where songs.csv and results live            (default ~/archive-audit)
#   AUDIT_CPUS     CPU cap for the container                   (default 15: ~75% of gameforge's 22 threads)
#   AUDIT_SOURCE   where the files are read from               (default: over SSH from bigballs)
#   AUDIT_DB       results file name inside AUDIT_DIR          (default results.sqlite)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo="$(cd "$here/../.." && pwd)"   # the measuring code lives in archive/lib/audio_audit
AUDIT_DIR=${AUDIT_DIR:-$HOME/archive-audit}
AUDIT_CPUS=${AUDIT_CPUS:-15}
AUDIT_SOURCE=${AUDIT_SOURCE:-ssh:sauce@192.168.17.109:/datatank/archive/psql_storage}
AUDIT_DB=${AUDIT_DB:-results.sqlite}
docker build -q -t archive-audit:local "$here" >/dev/null
ssh_mounts=()
if [[ $AUDIT_SOURCE == ssh:* ]]; then
  ssh_mounts=(-v "$HOME/.ssh/id_ed25519:/home/audit/.ssh/id_ed25519:ro" -v "$HOME/.ssh/known_hosts:/home/audit/.ssh/known_hosts:ro")
fi
local_mount=()
if [[ $AUDIT_SOURCE == local:* ]]; then
  local_mount=(-v "${AUDIT_SOURCE#local:}:${AUDIT_SOURCE#local:}:ro")
fi
exec docker run --rm --init --name "archive-audit-${AUDIT_DB%.*}" --network host --cpus "$AUDIT_CPUS" \
  --tmpfs /work:size=6g,uid=1000 -v "$AUDIT_DIR:/data" -v "$repo:/repo:ro" "${ssh_mounts[@]}" "${local_mount[@]}" \
  archive-audit:local python3 -I /repo/library_tools/audit/scan.py --songs /data/songs.csv --db "/data/$AUDIT_DB" --source "$AUDIT_SOURCE" "$@"
