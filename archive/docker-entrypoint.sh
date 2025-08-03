#!/bin/bash
set -e

if [ "$RAILS_ENV" = "production" ]; then
  bundle exec rails db:migrate
else
  bundle exec rails db:prepare
fi

exec "$@"