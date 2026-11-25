#!/usr/bin/env bash
# Run a command from the archive app against local staging.  WORK=<dir> mounts that directory at /work.
set -euo pipefail
. "$(dirname "$0")/common.sh"
trap 'rm -f "$REPO/archive/db/schema.rb"' EXIT
docker run --rm --network host --user "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "$REPO/archive":/rails -v archive_dev_bundle:/usr/local/bundle -v "$(cd "${WORK:-$STAGING_DIR/work}" && pwd)":/work \
  -e RAILS_ENV="${RAILS_ENV:-development}" -e SECRET_KEY_BASE=$STAGING_SECRET -e STAGING_TEST_PASSWORD \
  -e DATABASE_URL="$(db_url "${DB_NAME:-}")" -e REDIS_URL=redis://127.0.0.1:63799/1 \
  archive-dev "$@"
