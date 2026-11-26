#!/usr/bin/env bash
# Is production's database what the repository says it should be?
# Compares (1) the applied migration versions and (2) the schema itself with db/migrate and
# db/structure.sql of a git ref (default: master, which is what should be deployed).
# Read-only: uses the archive_clone login in ~/archive-clone.env.
#   bash schema_check.sh [git-ref]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$(cd "$HERE/../.." && pwd)"; REF="${1:-master}"
[ -f ~/archive-clone.env ] || { echo "no ~/archive-clone.env (read-only production login)" >&2; exit 2; }
set -a; . ~/archive-clone.env; set +a
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pg() { docker run --rm --network host -e PGPASSWORD -e PGHOST -e PGPORT -e PGUSER -e PGDATABASE postgres:15 "$@"; }
pg psql -At -c "select version from schema_migrations order by 1" > "$T/prod_versions"
pg pg_dump -s --no-owner --no-privileges --no-publications --no-subscriptions > "$T/prod.sql"
git -C "$REPO" show "$REF:archive/db/structure.sql" > "$T/repo.sql"
git -C "$REPO" ls-tree --name-only "$REF" archive/db/migrate/ | sed 's|.*/||; s/_.*//' | sort > "$T/file_versions"
python3 - "$T" "$REF" <<'PY'
import re, sys
T, ref = sys.argv[1], sys.argv[2]
prod = set(open(T + "/prod_versions").read().split()); files = set(open(T + "/file_versions").read().split())
def statements(path):
    text = open(path).read().split('INSERT INTO "schema_migrations"')[0]
    text = re.sub(r"--.*", "", text); text = re.sub(r"\\(un)?restrict.*", "", text)
    out = set()
    for st in text.split(";"):
        st = " ".join(st.split())
        if st and not st.startswith(("SET ", "SELECT pg_catalog")) and "PUBLICATION" not in st:
            out.add(st)
    return out
a, b = statements(T + "/prod.sql"), statements(T + "/repo.sql")
problems = 0
def report(title, items):
    global problems
    if items:
        problems += len(items)
        print(title)
        for item in sorted(items): print("   ", item[:200])
report("Applied in production but no migration file in %s:" % ref, prod - files)
report("Migration files in %s not applied in production (deploy pending?):" % ref, files - prod)
report("In production's schema but not in %s structure.sql:" % ref, a - b)
report("In %s structure.sql but not in production's schema:" % ref, b - a)
print("production vs %s: %d migrations, %d schema statements, %s" % (ref, len(prod), len(a), "IN SYNC" if not problems else "%d DIFFERENCES" % problems))
sys.exit(1 if problems else 0)
PY
