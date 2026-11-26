#!/usr/bin/env bash
# End-to-end run of server-side playback: the archive (staging web), station.py signed in with the
# node's player token, and a mock OwnTone. Covers taking over from a browser player mid-song,
# transport / volume / speakers from the remote, one jukebox taking the speakers from another,
# handing back, and a daemon restart mid-song (the music must not be interrupted).
# The daemon is run with LINE_UP_SECONDS=9999 (line the next song up at once) because several checks
# look at the lined-up song; in production it waits until the last 20 seconds of a song.
# Needs web.sh running. Touches only the test user's "E2E" jukeboxes.
#
#   bash server_player_e2e.sh                               # station.py straight from the repo
#   PLAYER_IMAGE=archive-player:dev bash server_player_e2e.sh   # the container image (docker build ../../station)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/common.sh"
mkdir -p "$STAGING_DIR/work"; cp "$HERE/server_player_e2e_setup.rb" "$STAGING_DIR/work/"
eval "$(bash "$HERE/rails.sh" bundle exec rails runner /work/server_player_e2e_setup.rb 2>/dev/null | grep -E '^(TOKEN|PARTY|OTHER|SONG)=')"
DATA=$(mktemp -d); chmod 777 "$DATA"; LOG=/tmp/server_player_e2e.log; : > $LOG; STN=
start_daemon() {
  if [ -n "${PLAYER_IMAGE:-}" ]; then
    docker run -d --name archive-player-e2e --network host -v "$DATA":/data -e ARCHIVE_URL=http://127.0.0.1:3909 -e NODE_TOKEN=$TOKEN \
      -e OWNTONE_URL=http://127.0.0.1:3691 -e BIND_HOST=127.0.0.1 -e BIND_PORT=8339 -e LINE_UP_SECONDS=${LINE_UP_SECONDS:-9999} "$PLAYER_IMAGE" >/dev/null
  else
    ARCHIVE_URL=http://127.0.0.1:3909 NODE_TOKEN=$TOKEN OWNTONE_URL=http://127.0.0.1:3691 BIND_HOST=127.0.0.1 BIND_PORT=8339 LINE_UP_SECONDS=${LINE_UP_SECONDS:-9999} \
    STATE_FILE="$DATA/station_state.json" python3 -u "$REPO/station/station.py" >> $LOG 2>&1 & STN=$!
  fi
}
stop_daemon() {
  if [ -n "${PLAYER_IMAGE:-}" ]; then docker logs archive-player-e2e >> $LOG 2>&1; docker rm -f archive-player-e2e >/dev/null 2>&1
  else [ -n "$STN" ] && kill $STN 2>/dev/null && wait $STN 2>/dev/null; fi
}
cleanup() { stop_daemon; kill $MOCK 2>/dev/null; rm -rf "$DATA"; }
trap cleanup EXIT
SONG_SECONDS=300 python3 "$REPO/station/test/mock_owntone.py" 3691 & MOCK=$!
docker rm -f archive-player-e2e >/dev/null 2>&1
start_daemon; sleep 2
PARTY=$PARTY OTHER=$OTHER SONG=$SONG python3 "$HERE/server_player_e2e.py"; status=$?

echo "== the daemon is restarted mid-song (a deploy): the music carries on"
PARTY=$PARTY python3 "$HERE/server_player_e2e.py" start-playing || status=1
curl -s -o /dev/null -w "  /up -> %{http_code}\n" http://127.0.0.1:8339/up
stop_daemon; start_daemon; sleep 6
PARTY=$PARTY python3 "$HERE/server_player_e2e.py" still-playing || status=1

echo "== daemon log"; stop_daemon; STN=; tail -12 $LOG | sed 's/^/  /'
[ $status = 0 ] && echo "E2E PASSED" || echo "E2E FAILED"
exit $status
