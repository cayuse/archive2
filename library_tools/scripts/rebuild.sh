#!/usr/bin/env bash
# Run the library rebuild on STAGING. Usage (inside WSL):  bash rebuild.sh [dry]
set -euo pipefail
D=/mnt/c/Users/cayuse/ai_stuff/music_archive/scripts
if [ "${1:-}" = "dry" ]; then
  exec bash "$D/rails.sh" env DRY_RUN=1 bundle exec rails "library:rebuild[/work/work/mb]"
fi
exec bash "$D/rails.sh" bundle exec rails "library:rebuild[/work/work/mb]"
