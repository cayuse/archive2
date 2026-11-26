#!/usr/bin/env bash
# The browser jukebox player across real song changes, in headless Chrome against staging (web.sh
# must be running). Needs google-chrome and node 22+, and songs with audio files on staging.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/common.sh"
mkdir -p "$STAGING_DIR/work"; cp "$HERE/browser_player_setup.rb" "$STAGING_DIR/work/"
eval "$(bash "$HERE/rails.sh" bundle exec rails runner /work/browser_player_setup.rb 2>/dev/null | grep -E '^(JUKEBOX|SONGS|REQUEST_SONG)=')"
[ -n "${JUKEBOX:-}" ] || { echo "setup failed"; exit 1; }
echo "jukebox $JUKEBOX, $SONGS songs with audio"
JUKEBOX=$JUKEBOX REQUEST_SONG=$REQUEST_SONG EMAIL=station-test@example.invalid PASSWORD=$STAGING_TEST_PASSWORD node "$HERE/browser_player_e2e.mjs"
