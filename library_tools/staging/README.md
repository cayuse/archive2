# Local staging on Linux (gameforge)

A throwaway copy of the archive database plus the app's own Rails, for developing against real
library data without touching production. Everything binds to 127.0.0.1. Staging has **no audio
files**: pages, the API and the radio work; actual playback returns an error.

State lives outside the repo in `$STAGING_DIR` (default `~/archive-staging`): a `.env` with the
database password (never in git) and a `work/` scratch directory mounted at `/work`.

```sh
bash setup.sh /path/to/archive_repaired_<stamp>.dump   # once: Postgres 15 + Redis containers, restore, dev image, gems
bash rails.sh bundle exec rails db:migrate             # any Rails command against staging
bash psql.sh -c "select count(*) from songs"
bash web.sh                                            # (re)start the app on http://127.0.0.1:3909 (production mode)
bash test.sh [files]                                   # the app's minitest suite in its own database
bash station_e2e.sh                                    # station.py's own control page (account login) against staging and a mock OwnTone
bash server_player_e2e.sh                              # server-side playback: node token, hand-off from a browser, remote transport
WORK=../scripts bash rails.sh bundle exec rails runner /work/station_engine_test.rb   # radio checks on real data
```

Notes:

- `web.sh` runs in production mode, to behave like the deployed app. Code is loaded once: rerun
  `web.sh` after changing Ruby or views.
- Rails commands write `archive/db/schema.rb`; the repo does not track it, so the scripts delete it.
- `setup.sh` creates a login for tests (`station-test@example.invalid`, password in `.env`).

## Browser player across song changes

`bash browser_player_e2e.sh` (web.sh running; needs google-chrome and node 22+) plays a staging
jukebox in headless Chrome through real song changes: the next song is taken only in the last
20 seconds, shown as "up next", started from the preload, and the gap between songs is measured;
skips mid-song and just after a prefetch are covered. It uses the songs whose audio files exist on
staging (the Drop Box imports). It cannot test iOS: no lock screen, no iOS audio rules.
