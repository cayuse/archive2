#!/usr/bin/env bash
# One-time setup of local staging. Usage: bash setup.sh /path/to/archive_repaired_<stamp>.dump
set -euo pipefail
DUMP="${1:?path to a pg_dump -Fc file of the archive database}"
STAGING_DIR="${STAGING_DIR:-$HOME/archive-staging}"
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$STAGING_DIR/work"
if [ ! -f "$STAGING_DIR/.env" ]; then
  ( umask 077
    pw() { head -c 18 /dev/urandom | base64 | tr -dc A-Za-z0-9; }
    printf 'POSTGRES_USER=postgres\nPOSTGRES_PASSWORD=%s\nPOSTGRES_HOST=127.0.0.1\nPOSTGRES_PORT=54329\nPOSTGRES_DB=archive_staging\nSTAGING_TEST_PASSWORD=%s\n' "$(pw)" "$(pw)" > "$STAGING_DIR/.env" )
fi
. "$HERE/common.sh"
docker inspect archive-staging-db >/dev/null 2>&1 || docker run -d --name archive-staging-db -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
  -p "127.0.0.1:$POSTGRES_PORT:5432" -v archive_staging_pg:/var/lib/postgresql/data postgres:15 >/dev/null
docker inspect archive-staging-redis >/dev/null 2>&1 || docker run -d --name archive-staging-redis -p 127.0.0.1:63799:6379 redis:7-alpine >/dev/null
until docker exec archive-staging-db pg_isready -U postgres >/dev/null 2>&1; do sleep 1; done
docker exec archive-staging-db createdb -U postgres "$POSTGRES_DB"
docker exec -i archive-staging-db pg_restore -U postgres -d "$POSTGRES_DB" --no-owner < "$DUMP"
docker image inspect archive-dev >/dev/null 2>&1 || docker build -q -t archive-dev "$REPO/library_tools/rails-dev"
docker run --rm -v archive_dev_bundle:/usr/local/bundle archive-dev chown -R "$(id -u):$(id -g)" /usr/local/bundle
bash "$HERE/rails.sh" bundle install
bash "$HERE/rails.sh" bundle exec rails db:migrate
bash "$HERE/rails.sh" bundle exec rails runner "u = User.find_or_initialize_by(email: 'station-test@example.invalid'); u.assign_attributes(name: 'Station Test', password: ENV.fetch('STAGING_TEST_PASSWORD'), password_confirmation: ENV.fetch('STAGING_TEST_PASSWORD'), role: 'admin'); u.save!; puts 'test user ready'"
