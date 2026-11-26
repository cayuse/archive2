#!/usr/bin/env bash
# End-to-end run of station/station.py against the staging web server and a mock OwnTone.
# Needs web.sh running. Read-only apart from the test user's stations and feedback.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/common.sh"
cleanup() { kill $MOCK $STN 2>/dev/null; }
trap cleanup EXIT
SONG_SECONDS=10 python3 "$REPO/station/test/mock_owntone.py" 3690 & MOCK=$!
ARCHIVE_URL=http://127.0.0.1:3909 ARCHIVE_EMAIL=station-test@example.invalid ARCHIVE_PASSWORD=$STAGING_TEST_PASSWORD \
OWNTONE_URL=http://127.0.0.1:3690 BIND_HOST=127.0.0.1 BIND_PORT=8338 STATE_FILE=/tmp/station_e2e_state.json \
  python3 -u "$REPO/station/station.py" > /tmp/station_e2e.log 2>&1 & STN=$!
rm -f /tmp/station_e2e_state.json; sleep 2
S=http://127.0.0.1:8338
post() { curl -s -X POST -H 'Content-Type: application/json' -d "$2" "$S$1"; }
show() { python3 -c "
import json,sys; s=json.load(sys.stdin); c=s.get('current') or {}; j=s.get('jukebox') or {}
print('  playing=%s station=%r current=%s - %s standing=%s error=%s' % (s['playing'], j.get('name'), c.get('artist'), c.get('title'), s.get('standing'), s.get('error')))
print('  radio=%s' % json.dumps(j.get('radio')))
for u in s.get('upcoming', [])[:4]: print('    next: %-9s %s - %s' % (u['source'], u['artist'], u['title']))"; }
cur() { curl -s $S/api/state | python3 -c "import json,sys; print((json.load(sys.stdin).get('current') or {}).get('id',''))"; }
echo "== page"; curl -s -o /dev/null -w "  GET / -> %{http_code} %{size_download} bytes\n" $S/
echo "== stations"; curl -s $S/api/stations | python3 -c "import json,sys; print('  ', [s['name'] for s in json.load(sys.stdin)['stations']])"
SONG=$(curl -s "$S/api/search?q=whole+lotta+love" | python3 -c "import json,sys; print(json.load(sys.stdin)['songs'][0]['id'])")
echo "== new station from Whole Lotta Love"; post /api/start "{\"song_id\":\"$SONG\",\"new\":true}" >/dev/null; sleep 6; curl -s $S/api/state | show
echo "== thumbs up the current song"; post /api/feedback "{\"song_id\":\"$(cur)\",\"kind\":\"up\"}" | show
echo "== wait for it to finish (10 s songs)"; sleep 11; curl -s $S/api/state | show
echo "== sick of the current song (should move on, no dislike)"; T=$(cur); post /api/feedback "{\"song_id\":\"$T\",\"kind\":\"tired\"}" >/dev/null; sleep 4; curl -s $S/api/state | show; [ "$(cur)" != "$T" ] && echo "  moved on: yes" || echo "  moved on: NO"
echo "== skip (reported as a skip)"; post /api/skip '{}' >/dev/null; sleep 4; curl -s $S/api/state | show
echo "== mellow and steady"; post /api/settings '{"intensity":-0.7,"variety":0.1,"genre":"adjacent"}' | show
echo "== old page's /api/rate still works"; post /api/rate "{\"song_id\":\"$(cur)\",\"value\":1}" | python3 -c "import json,sys; print('  standing=%s' % json.load(sys.stdin).get('standing'))"
echo "== switch to the first station"; FIRST=$(curl -s $S/api/stations | python3 -c "import json,sys; print(json.load(sys.stdin)['stations'][0]['id'])"); post /api/start "{\"station_id\":\"$FIRST\"}" >/dev/null; sleep 5; curl -s $S/api/state | show
echo "== stop"; post /api/stop '{}' | python3 -c "import json,sys; s=json.load(sys.stdin); print('  playing=%s' % s['playing'])"
echo "== what the archive recorded"
bash "$HERE/psql.sh" -At -F' | ' -c "select f.kind, round(f.position::numeric,0), st.name, left(s.title,40) from station_feedbacks f join users u on u.id=f.user_id left join stations st on st.id=f.station_id join songs s on s.id=f.song_id where u.email='station-test@example.invalid' and f.created_at > now() - interval '3 minutes' order by f.created_at" | sed 's/^/  /'
echo "== station log tail"; tail -8 /tmp/station_e2e.log | sed 's/^/  /'
