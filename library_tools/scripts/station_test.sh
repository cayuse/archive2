#!/usr/bin/env bash
# End-to-end test of the headless station against STAGING, with a mock OwnTone (no real speakers).
# Runs inside WSL:  bash station_test.sh
set -uo pipefail
ROOT=/mnt/c/Users/cayuse/ai_stuff/music_archive
REPO=/mnt/c/Users/cayuse/Documents/archive2
set -a; . "$ROOT/.env"; set +a
DB="postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@localhost:$POSTGRES_PORT/$POSTGRES_DB"
RUN="docker run --rm --network host -v $REPO/archive:/rails -v archive_dev_bundle:/usr/local/bundle -v $ROOT:/work
     -e RAILS_ENV=production -e SECRET_KEY_BASE=staging-test-key-0123456789abcdef0123456789abcdef -e DATABASE_URL=$DB
     -e RAILS_LOG_TO_STDOUT=1 -e INLINE_AUDIO_PROCESSING=true -e PORT=3009"
PASS=station-test-pw
cleanup() { docker rm -f archive-staging-web >/dev/null 2>&1; kill $MOCK $STN 2>/dev/null; }
trap cleanup EXIT

echo "== test user + server"
$RUN archive-dev bundle exec rails runner "u = User.find_or_initialize_by(email: 'station-test@example.invalid'); u.assign_attributes(name: 'Station Test', password: '$PASS', password_confirmation: '$PASS', role: 'admin'); u.save!; puts 'user ok ' + u.role" 2>&1 | tail -1
docker rm -f archive-staging-web >/dev/null 2>&1
$RUN -d --name archive-staging-web archive-dev bundle exec rails server -b 127.0.0.1 -p 3009 >/dev/null
for i in $(seq 1 60); do curl -s -o /dev/null "http://127.0.0.1:3009/up" && break; sleep 2; done
curl -s -o /dev/null -w "server /up -> %{http_code}\n" http://127.0.0.1:3009/up

SONG_SECONDS=12 python3 "$REPO/station/test/mock_owntone.py" 3690 & MOCK=$!
ARCHIVE_URL=http://127.0.0.1:3009 ARCHIVE_EMAIL=station-test@example.invalid ARCHIVE_PASSWORD=$PASS \
OWNTONE_URL=http://127.0.0.1:3690 BIND_HOST=127.0.0.1 BIND_PORT=8338 STATE_FILE=/tmp/station_test_state.json \
  python3 -u "$REPO/station/station.py" > /tmp/station_test.log 2>&1 & STN=$!
sleep 2
S=http://127.0.0.1:8338
post() { curl -s -X POST -H 'Content-Type: application/json' -d "$2" "$S$1"; }
show() { python3 -c "
import json,sys; s=json.load(sys.stdin); c=s.get('current') or {}
print('  playing=%s current=%s - %s | error=%s' % (s['playing'], c.get('artist'), c.get('title'), s.get('error')))
print('  radio=%s' % json.dumps((s.get('jukebox') or {}).get('radio')))
for u in s.get('upcoming', [])[:5]: print('    next: %-9s %s - %s' % (u['source'], u['artist'], u['title']))"; }

echo "== control page"; curl -s -o /dev/null -w "  GET / -> %{http_code} %{size_download} bytes\n" $S/
echo "== search 'whole lotta love'"
SONG=$(curl -s "$S/api/search?q=whole+lotta+love" | python3 -c "import json,sys; s=json.load(sys.stdin)['songs']; print(s[0]['id']); print('  %d results, first: %s - %s' % (len(s), s[0]['artist'], s[0]['title']), file=sys.stderr)")
echo "== start from that song"; post /api/start "{\"song_id\":\"$SONG\"}" >/dev/null; sleep 7; curl -s $S/api/state | show
echo "== 14 s later (mock songs last 12 s)"; sleep 14; curl -s $S/api/state | show
echo "== steer: mellower + strict genre"; post /api/settings '{"energy":-0.6,"genre":"strict"}' >/dev/null; sleep 5; curl -s $S/api/state | show
echo "== request a different song (should play next and re-aim)"
REQ=$(curl -s "$S/api/search?q=george+strait" | python3 -c "import json,sys; print(json.load(sys.stdin)['songs'][0]['id'])")
post /api/request "{\"song_id\":\"$REQ\"}" >/dev/null; sleep 4; curl -s $S/api/state | show; echo "   ...after the current song ends"; sleep 12; curl -s $S/api/state | show
echo "== thumbs down the current song (should skip it)"
CUR=$(curl -s $S/api/state | python3 -c "import json,sys; print((json.load(sys.stdin).get('current') or {}).get('id',''))")
post /api/feedback "{\"song_id\":\"$CUR\",\"kind\":\"down\"}" >/dev/null; sleep 4; curl -s $S/api/state | show
echo "== non-LAN caller is refused"; curl -s -o /dev/null -w "  with X-Forwarded-For: 8.8.8.8 -> %{http_code}\n" -H 'X-Forwarded-For: 8.8.8.8' $S/api/state
echo "== stop"; post /api/stop '{}' | python3 -c "import json,sys; s=json.load(sys.stdin); print('  playing=%s' % s['playing'])"
echo "== what the mock speaker played"; curl -s http://127.0.0.1:3690/mock/log | python3 -c "import json,sys; p=json.load(sys.stdin)['played']; print('  %d songs; link looks like %s' % (len(p), p[0][:60] if p else None))"
echo "== play link really streams audio?"; L=$(curl -s http://127.0.0.1:3690/mock/log | python3 -c "import json,sys; print(json.load(sys.stdin)['played'][0])"); curl -s -o /dev/null -r 0-99 -w "  GET play link -> %{http_code} %{content_type}\n" "$L"
echo "== station log tail"; tail -12 /tmp/station_test.log
echo "== cleanup test data"
$RUN archive-dev bundle exec rails runner "u = User.find_by(email: 'station-test@example.invalid'); Jukebox.where(owner_id: u.id).destroy_all; StationFeedback.where(user_id: u.id).delete_all; u.destroy; puts 'removed test user, stations and feedback'" 2>&1 | tail -1
rm -f "$REPO/archive/db/schema.rb"
