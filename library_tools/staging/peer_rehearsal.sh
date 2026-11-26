#!/usr/bin/env bash
# Rehearse a release with migrations on the gameforge test pair before doing it for real
# (docs/PEERS.md, "Continued development"): the stand-in for bigballs (peer-sim-bigballs-db, schema
# primary) is migrated from the working tree, then the gameforge peer is deployed and migrated, and
# both are compared: schema fingerprint of the shared tables, subscriptions, how far behind.
#
#   bash peer_rehearsal.sh            migrate both
#   bash peer_rehearsal.sh rollback   roll the last migration back on both (primary first)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$(cd "$HERE/../.." && pwd)"
. "$HOME/.config/archive/peers/bigballs-sim.env"
TASK=${1:-migrate}; [ "$TASK" = rollback ] && RAKE=db:rollback || RAKE=db:migrate
SIM_URL="postgres://postgres:$SIM_PASSWORD@192.168.17.97:5443/archive_production"
P=(-c config/deploy.peer.yml -d gameforge)
sim() { docker run --rm --network host -v "$REPO/archive":/rails -v archive_dev_bundle:/usr/local/bundle --user "$(id -u):$(id -g)" \
          -e HOME=/tmp -e RAILS_ENV=production -e SECRET_KEY_BASE=x -e PEER_SCHEMA_PRIMARY=true -e DATABASE_URL="$SIM_URL" \
          archive-dev bundle exec rails "$@" 2>&1 | grep -v "wal_level\|HINT"; }
peer() { (cd "$REPO/archive" && kamal app exec "bin/rails $1" "${P[@]}" --roles web --reuse 2>&1 | grep -v "^\s*INFO\|^App Host\|^Launching\|^Get \|^$"); }

echo "== 1. the stand-in for bigballs (schema primary): $RAKE"; sim "$RAKE"
sleep 5
if [ "$TASK" = migrate ]; then
  echo "== 2. the gameforge peer: deploy the new code"; (cd "$REPO/archive" && kamal deploy "${P[@]}" 2>&1 | grep -E "ERROR|Finished all")
fi
echo "== 3. the gameforge peer: $RAKE"; peer "$RAKE"
sleep 3
echo "== 4. compare"; echo "-- bigballs (stand-in):"; sim peer:status; echo "-- gameforge:"; peer peer:status
