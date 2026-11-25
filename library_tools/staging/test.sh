#!/usr/bin/env bash
# Run the app's minitest suite (or the given files) in its own database, built from the staging schema.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/common.sh"
docker run --rm --network host --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$REPO/archive":/rails -v archive_dev_bundle:/usr/local/bundle \
  -e SECRET_KEY_BASE=$STAGING_SECRET -e SOURCE="$(db_url)" -e TEST="$(db_url archive_test)" archive-dev sh -c '
    DATABASE_URL=$SOURCE RAILS_ENV=development bundle exec rails db:schema:dump >/dev/null &&
    DATABASE_URL=$TEST RAILS_ENV=test DISABLE_DATABASE_ENVIRONMENT_CHECK=1 bundle exec rails db:drop db:create db:schema:load >/dev/null &&
    DATABASE_URL=$TEST RAILS_ENV=test bundle exec rails test "$@"' sh "$@"
status=$?
rm -f "$REPO/archive/db/schema.rb"
exit $status
