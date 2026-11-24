#!/usr/bin/env bash
# Run a command from the archive app (Rails 8, Ruby 3.2.5) against the LOCAL staging database.
# Usage inside WSL:
#   bash rails.sh bundle exec rails g model Thing name:string
#   bash rails.sh bundle exec rails db:migrate
# The app checkout is mounted from Windows; gems live in the docker volume archive_dev_bundle.
set -euo pipefail
ROOT=/mnt/c/Users/cayuse/ai_stuff/music_archive
REPO=/mnt/c/Users/cayuse/Documents/archive2/archive
set -a; . "$ROOT/.env"; set +a

if ! docker image inspect archive-dev >/dev/null 2>&1; then
  docker build -q -t archive-dev "$ROOT/rails-dev"
fi

exec docker run --rm --network host \
  -v "$REPO":/rails -v archive_dev_bundle:/usr/local/bundle -v "$ROOT":/work \
  -e RAILS_ENV=development \
  -e DATABASE_URL="postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@localhost:$POSTGRES_PORT/$POSTGRES_DB" \
  -e POSTGRES_USER -e POSTGRES_PASSWORD -e POSTGRES_HOST -e POSTGRES_PORT \
  archive-dev "$@"
