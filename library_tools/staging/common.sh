# Sourced by the staging scripts.
STAGING_DIR="${STAGING_DIR:-$HOME/archive-staging}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[ -f "$STAGING_DIR/.env" ] || { echo "no $STAGING_DIR/.env - run setup.sh first" >&2; exit 1; }
set -a; . "$STAGING_DIR/.env"; set +a
# read-only login for the MusicBrainz mirror (optional; without it nothing is looked up)
[ -f "$STAGING_DIR/musicbrainz.env" ] && { set -a; . "$STAGING_DIR/musicbrainz.env"; set +a; }
STAGING_SECRET=staging-test-key-0123456789abcdef0123456789abcdef
db_url() { echo "postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@127.0.0.1:$POSTGRES_PORT/${1:-$POSTGRES_DB}"; }
