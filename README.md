# Archive

A self-hosted music archive (Rails 8, Postgres) with a party jukebox, personal radio stations and
server-side playback to AirPlay speakers.

| Directory | What it is |
|---|---|
| `archive/` | The Rails app: library, uploads, playlists, the jukebox (AJB), stations, the API. |
| `station/` | The player: a small daemon that plays whichever jukebox has been put on a node's speakers, plus OwnTone (AirPlay). Its own Kamal service. See `station/README.md`. |
| `owntone/` | OwnTone's configuration (used by `station/`). |
| `library_tools/` | Library maintenance tools and the staging harness (`library_tools/staging/`). |
| `utilities/` | Bulk upload and tag-extraction scripts that talk to the API. |
| `docs/` | Documentation. Start at `docs/README.md`. |

## Run it locally

```sh
cd archive
docker compose -f docker-compose.dev.yml up      # http://localhost:3000, admin@musicarchive.com / admin123
```

First boot loads `db/structure.sql` and seeds 25 generated songs. `docker compose -f docker-compose.dev.yml down -v`
throws the database away.

## Working on it

1. Branch from `master`.
2. Run the checks: `bin/check` (tests, security scan, daemon syntax). They also run in CI on every push
   and pull request (`.github/workflows/ci.yml`). The suite must be green; a failing test is fixed or the
   change is not merged.
3. Try it on staging: a production-copy database on the dev machine (`library_tools/staging/README.md`).
   `server_player_e2e.sh` and `station_e2e.sh` there exercise the player end to end.
4. Merge to `master` and deploy.

Schema: `archive/db/structure.sql` is the source of truth (SQL format). A change is a migration in
`archive/db/migrate/` plus the regenerated `structure.sql`, committed together. `bin/check --schema`
compares production's schema and migration list with the repository.

## Deploy

Production is one host. Two Kamal services, deployed separately:

| Service | From | Runbook |
|---|---|---|
| `archive` (the app) | `cd archive && kamal deploy` | `archive/KAMAL_DEPLOY.md` |
| `archive-player` (daemon + OwnTone) | `cd station && kamal deploy` | `station/README.md` |

Back up before any deploy that carries a migration; migrations are run by hand after the deploy
(`kamal app exec --reuse "bin/rails db:migrate"`). Secrets live in `~/.config/archive/` on the
deploying machine, never in git.
