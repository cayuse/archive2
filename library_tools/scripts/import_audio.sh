#!/usr/bin/env bash
# Load the built vectors into STAGING, then (optionally) print radio streams.
# Usage (inside WSL): bash import_audio.sh            import only
#                     bash import_audio.sh radio <song_id> [STEER]   e.g. radio <id> energy=-1
set -euo pipefail
D=/mnt/c/Users/cayuse/ai_stuff/music_archive/scripts
if [ "${1:-}" = "radio" ]; then
  exec bash "$D/rails.sh" env STEER="${3:-}" bundle exec rails "library:radio[$2,12]"
fi
exec bash "$D/rails.sh" bundle exec rails "library:import_audio[/work/work/audio/out]"
