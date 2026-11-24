#!/usr/bin/env bash
# One-off: thumbs up/down per user, and learned genre adjacency.
set -euo pipefail
bundle exec rails g model SongRating user:references song:references value:integer --no-fixture
sleep 1
bundle exec rails g model GenreAffinity genre:references related_genre:references score:float --no-fixture
