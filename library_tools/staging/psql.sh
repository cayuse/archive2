#!/usr/bin/env bash
# psql against the local staging database.  bash psql.sh -c "select 1"   or   bash psql.sh < file.sql
. "$(dirname "$0")/common.sh"
exec docker exec -i archive-staging-db psql -U postgres -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 "$@"
