#!/usr/bin/env bash
# (Re)start the staging web server on http://127.0.0.1:3909, production mode, against the staging DB,
# and the intake worker beside it (the Drop Box needs both).
#   BIND=0.0.0.0 bash web.sh     also reachable from other machines on the network (for trying pages by hand)
set -euo pipefail
. "$(dirname "$0")/common.sh"
docker rm -f archive-staging-web archive-staging-intake >/dev/null 2>&1 || true
mkdir -p "$STAGING_DIR/intake"
docker run -d --name archive-staging-web --network host --user "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "$REPO/archive":/rails -v archive_dev_bundle:/usr/local/bundle -v "$STAGING_DIR/intake":/intake \
  -e INTAKE_ROOT=/intake -e MUSICBRAINZ_URL \
  -e RAILS_ENV=production -e SECRET_KEY_BASE=$STAGING_SECRET -e REDIS_URL=redis://127.0.0.1:63799/1 \
  -e RAILS_LOG_TO_STDOUT=1 -e RAILS_SERVE_STATIC_FILES=1 -e INLINE_AUDIO_PROCESSING=true \
  -e DATABASE_URL="$(db_url)" archive-dev bundle exec rails server -b "${BIND:-127.0.0.1}" -p 3909 >/dev/null
docker run -d --name archive-staging-intake --network host --user "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "$REPO/archive":/rails -v archive_dev_bundle:/usr/local/bundle -v "$STAGING_DIR/intake":/intake \
  -e INTAKE_ROOT=/intake -e MUSICBRAINZ_URL -e RAILS_ENV=production -e SECRET_KEY_BASE=$STAGING_SECRET \
  -e RAILS_LOG_TO_STDOUT=1 -e DATABASE_URL="$(db_url)" archive-dev bundle exec rails intake:work >/dev/null
for i in $(seq 1 40); do curl -s -o /dev/null http://127.0.0.1:3909/up && break; sleep 2; done
curl -s -o /dev/null -w "staging web /up -> %{http_code}\n" http://127.0.0.1:3909/up
