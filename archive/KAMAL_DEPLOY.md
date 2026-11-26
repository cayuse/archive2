# Deploying Archive with Kamal (from gameforge)

Kamal manages **only the Rails app container**. Postgres (`archive-db-1`) and
Redis (`archive-redis-1`) keep running in the docker compose project on bigballs
and are never stopped, recreated or migrated by a deploy. (The DB used to be the
logical-replication master for standalone jukebox machines. Those are retired and their
replication slots dropped; the publication `pub_archive` and a few empty tables remain.)

## How the containers are separated on bigballs
| Network | Members | Purpose |
|---|---|---|
| `archive_default` | archive-db-1, archive-redis-1, the archive app | Archive only |
| `kamal` | sauce-postgis, sauce/jeehq/jeesauce-www apps | The other apps |

The archive app connects by the unique container names `archive-db-1` /
`archive-redis-1`, and `post-app-boot` detaches it from the `kamal` network, so
it can neither reach nor be confused with `sauce-postgis`.

## One-time setup on the deploying machine
1. `~/.config/archive/production.env` (chmod 600): copy of bigballs `~/cavaforge.txt`.
2. `config/credentials.yml.enc` (gitignored) from bigballs `~/archive2/archive/config/`.
3. GHCR token readable at `/home/sauce/secrets/jeedata/ghcr.env` (shared with the other apps).

The hooks refuse to deploy if any of these is missing or empty.

## Every deploy
```bash
cd ~/src/archive2/archive
kamal deploy                 # build, push to ghcr.io/cayuse/archive, swap the app (a few seconds of 502s)
kamal logs                   # tail
kamal console                # rails console
```
Migrations do NOT run automatically (the entrypoint only runs db:prepare when
RUN_DB_SETUP_ON_START=true). When a release adds migrations: back up first (below), then
`kamal app exec "bin/rails db:migrate"`.

## Backup (always before a cutover or migration)
```bash
ssh cayuse@192.168.17.109 'D=~/archive-backups/$(date +%Y%m%d-%H%M%S); mkdir -p $D &&
  docker exec archive-db-1 pg_dump -U postgres -Fc -d archive_production > $D/archive_production.dump &&
  docker exec archive-db-1 pg_dumpall -U postgres --globals-only > $D/globals.sql && cd $D && sha256sum * > SHA256SUMS'
scp -r cayuse@192.168.17.109:archive-backups/<stamp> ~/archive-backups/
```

## First cutover from compose (one time)
1. Fresh backup (above), copied to gameforge.
2. `kamal deploy`. `pre-app-boot` **stops** (does not remove) the compose app
   container `archive-archive-1` to free :3000, then the Kamal container boots.
3. Verify: `curl -s -o /dev/null -w '%{http_code}' https://archive.cavaforge.net/up` → 200, log in, play a song, check a jukebox.
4. Don't run `docker compose up` in ~/archive2/archive on bigballs afterwards (that would
   restart the old app container and fight for :3000). To manage db/redis use
   `docker compose up -d db redis`.

## Rollback
- To the previous Kamal version: `kamal rollback <version>` (`kamal app containers` lists them).
- All the way back to compose: `kamal app stop` then on bigballs `docker start archive-archive-1`.

## Staging (gameforge, never touches bigballs)
`kamal deploy -d staging` deploys to gameforge itself on 127.0.0.1:3900. It expects local
containers named archive-db-1 / archive-redis-1 on a local `archive_default` network
(e.g. a backup restored with pg_restore) and storage at /srv/archive-staging/storage.
This setup was used to rehearse the first cutover (2026-10-16); the containers were removed afterwards.
