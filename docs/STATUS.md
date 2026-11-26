# Status: what is built, what is deployed, what is not

Session handoff as of 2026-11-25. Written so this work can be picked up cold.

## What is DONE and DEPLOYED to production (slices I–IV: `9a93f20`; slice V: `600556d`, 2026-11-25)

Branch `feature/radio-multipeer` (merged to `master`, pushed, deployed via Kamal
to bigballs, migrations applied, verified healthy). Four slices:

- **I — Archive-node registry + per-user local-playback grants.**
  `archive_nodes` (this node + any peer that offers local playback; `node_id`
  matches `system_settings.archive_node_id`, plus `name`, `player_url`,
  `lan_cidr`). `playback_grants` (has_many :through, UUID PK — replication-safe).
  `User#can_play_on?`, `User has_many :playback_nodes`. Admin user-edit shows
  per-node "Local playback" checkboxes. **Named `ArchiveNode`, not `Archive`,
  because the app itself is `module Archive`** (collision — see gotchas).
- **II — `server_playback` mode flag + show-page switch.** `jukeboxes.server_playback`
  boolean. Owner-only switch on the jukebox show page, shown only where local
  playback is available to that user; `PATCH /jukeboxes/:id/server_playback`.
  **LAN-local gating was dropped on purpose** (per owner: remote control incl. a
  remote Stop is useful; only a couple of users). The permission grant alone
  gates it; every toggle is still validated server-side (`authorize_local_playback!`
  → 403).
- **III — Browser player restores & resumes on reopen.** Fixes the host player
  coming up "Nothing playing" and resetting position when reopened mid-play.
  Server `playback_status` now only applies position/is_playing when the heartbeat
  carries a `current_song_id` (a fresh page's null-song heartbeat no longer
  clobbers). `status` endpoint returns `current_song`/`current_position`/
  `is_playing`/`server_playback`. `PlayerController.restoreFromServer()` adopts it
  on open (paused, ready); `play()` resumes at the saved spot; `AudioEngine.loadAndPlay`
  gained a `startAt`.
- **IV — `/player` controller fork.** When `server_playback` is on, `/player`
  renders `jukeboxes/controller.html.erb`: a passive remote (live status polled
  from `/status`, a link to the node's `player_url`, no Howler), so closing/
  reopening it can't affect playback. Browser mode unchanged.

- **V — Server-side playback, end to end (deployed 2026-11-25, `600556d`).**
  The archive holds the desired state; the node's daemon (`station/station.py`) follows it.
  - *State.* `jukeboxes.server_transport` (play/pause/stop). `archive_nodes.player_token`
    (daemon's secret, `X-Node-Token`), `player_commands` (one-shot: skip/volume/output/retune, 30 s
    TTL, acked by seq), `player_state` + `player_seen_at` (what the daemon reports: speakers, volume, error).
  - *One jukebox on air.* `Jukebox#start_server_playback!` takes the speakers from any other
    jukebox; `end_server_playback!` gives them back; `transport!` is play/pause/stop/skip.
  - *Daemon.* Polls `POST /api/v1/node_player/sync` every 2 s, plays whichever jukebox is on air
    (party queue or radio, any owner) using the ordinary jukebox API with the node token (acting
    for the jukebox's owner, only while it is on air). Without `NODE_TOKEN` it polls as its account
    and plays only that account's jukeboxes. Its LAN control page is now just another remote: Start
    puts a station on the speakers through the archive.
  - *Hand-off.* Browser → speakers: the archive extrapolates the browser's position from its last
    heartbeat, the daemon loads the same song and seeks there; the browser player is told (cable
    message, or its next heartbeat answer) and reloads into the remote. Speakers → browser: the
    archive records the position, the daemon stops, an open remote reloads into the browser player
    restored paused at that spot (browsers will not autoplay); if no page is open it just stops.
  - *Remote.* `/jukeboxes/:id/player` in server mode: play/pause, skip, stop, thumbs (radio),
    volume, speaker selection, up next, daemon-offline warning, "give the speakers back". All of it
    goes through the archive (`POST /api/v1/jukeboxes/:id/transport`, `/server_playback`,
    `/api/v1/node_player/command`), so it works from anywhere and the daemon stays bound to
    localhost. `player_url` is optional now. Admin-code guests' play/pause/skip reach the daemon too.
  - *Stations.* "Play on <node>'s speakers" buttons on the station list and tuning pages.
  - *Admin.* Settings → Speakers (`/archive_node`): name, local playback on/off, player URL, the
    player token (+ regenerate), daemon status.
  - *Security.* `jukeboxes#show` and `#player` are owner-only (they showed guest/admin codes and
    minted a token for any moderator+). A non-string join code is a 401, not a 500.
  - *Tests.* `test/models/jukebox_server_playback_test.rb`, `test/controllers/api/v1/node_player_test.rb`;
    `library_tools/staging/server_player_e2e.sh` (node-token mode) and `station_e2e.sh` (account mode).
  - *Packaging.* The player is its own Kamal service, `archive-player`, in `station/`
    (`Dockerfile`, `config/deploy.yml`, `.kamal/`, `README.md` runbook): the daemon as the app image
    and OwnTone as a host-network accessory (a Kamal app cannot be host-networked). `GET /up`
    health check; the daemon remembers what it handed OwnTone (`/data` volume), so a deploy or
    restart mid-song carries on without touching the queue. `owntone.conf` trusts Docker's
    bridge ranges so the bridged daemon may use OwnTone's API. `station/docker-compose.yml` is
    the same pair for a node without Kamal. Deployed: bigballs runs `archive-player-player-<sha>`
    and `archive-player-owntone`; the old hand-started `owntone` and `archive-station` containers
    are stopped (not removed) for rollback.
  - *Known limits.* The daemon keeps one song lined up in OwnTone, so a request on a non-steering
    party queue plays after that song. Seeking on takeover needs OwnTone to be playing first, so
    the first second or two of the song may be heard before it jumps. Daemon restart mid-song
    restarts that song at the estimated position (brief gap).

### Production state right now
- Node row: `name="Home"`, `local_playback=true`, `player_url=http://192.168.17.109:8337`
  (the daemon's own control page, published on the LAN address only), player token set.
- Player secrets: `~/.config/archive/player.env` on gameforge (`NODE_TOKEN`, plus the account the
  old daemon used, for the control page's search / station list). Regenerating the token in
  Settings → Speakers means updating that file and `kamal deploy` in `station/`.
- Backups before deploys: `~/archive-backups/20261125-203625` (I–IV) and `20261125-211015` (V) on bigballs (dump +
  globals + SHA256SUMS). Rollback: `kamal rollback <ver>` or pg_restore.
- Not yet done on real speakers: nobody has pressed Play since the cutover. The daemon is online
  and sees the speakers, but its pause and seek calls have only run against the mock OwnTone.

## UNFINISHED — in rough priority order

### 1. DONE — the durable `Station` (deployed 2026-11-25)
Tested on staging (model tests, the API with two users, both player end-to-end scripts). Deploying
it is one archive deploy + `db:migrate` (`20261126150000_create_stations`, which converts every
existing station/radio jukebox and its feedback); the player daemon is unchanged.

- **`Station`** (`app/models/station.rb`): durable, user-owned, UUID, `origin_archive` stamp. Holds
  the recipe in `settings` (seeds, genre, steer, intensity, variety, learn, kept artists — the old
  `jukeboxes.radio_settings` shape) and owns the feedback log.
- **Jukebox is the runtime.** `jukeboxes.station_id`. Each station has a runtime jukebox on this
  node (`station-…` session id, `Station#runtime!`, made on first use), and the station pages, API
  and daemon still address a station by that jukebox's id — so nothing client-side had to change.
  A party jukebox on radio fill gets a private ("implicit") station on first use, or can be bound
  to one of the owner's stations in its edit form.
- **Feedback is an append-only log** on `station_feedbacks.station_id`: up / down / clear / skip /
  finished. The newest thumb or clear per song counts. `tired` / `never` belong to the person
  (no station), so a copy never inherits someone's banned songs.
- **Name**: "<seed song> Radio" (or "<playlist> Radio"), following the first seed until the owner
  renames it (`name_edited`).
- **From a playlist**: `station_playlists` links by reference, mode `inspire` (a few of its songs
  join the seeds on every top-up, the station plays what sounds like them) or `only` (stays
  inside the playlist). Editing the playlist changes the station.
- **Copies without copying**: a copy is one row (`parent_id`, `forked_at`). It reads the parent's
  log up to `forked_at` plus its own (`Station#lineage`, `StationFeedback.log_for`); its own thumbs
  override inherited ones; the original never changes. Snapshot, not follow (owner's decision).
- **Sharing**: per-station `shared` switch (off by default) on the tuning page. Shared stations
  are listed in the "Shared stations" table on the stations page (who shares it, who made it
  originally if it is a copy, what it is built on, thumbs taught, copies made). Being listed copies
  nothing; "Add to my stations" is what makes the person's own copy.
- **Delete**: the owner can always delete. With copies it is archived (`archived_at`, hidden) so
  the copies keep their base; when the last copy goes, the archived original is pruned.
- **Recipe digest**: SHA-256 of seeds + tuning + linked playlists. Starting a station whose recipe
  the person already has returns the existing one; also a cheap change check for sync later.
- Known behaviour: an `inspire` playlist station plays songs that sound like the playlist, so the
  playlist's own songs turn up only when they are close neighbours of each other.
- Still gated on sync (#6): actually moving a station to another peer. The model is ready for it
  (UUIDs, origin stamp, append-only log that merges by union); nothing is wired.

### 2–5. DONE — server-side playback end to end (slice V above)
Old items 2 (daemon drives any jukebox, hand-off, transport), 3 (node admin UI), 4 (`player_url`
reachability) and 5 (code leak on `show`) are closed and deployed.

### 6. Sync extension (DEFERRED by owner — "don't mess with syncing")
Existing jukeboxes are slave-only player endpoints; true peer sync has never been
attempted and is out of scope for now. For the record, when it's time:
- `pub_archive` (pg logical replication, master→slaves) publishes only 15 core
  tables; the new metadata is NOT replicated: `song_file_tags`,
  `song_audio_features`, `song_embeddings`, `song_neighbors`,
  `song_artist_credits`, `genre_affinities` (FKs all point only at published
  tables, so adding them is safe one-way). Keep node-local (do NOT publish):
  `jukeboxes`, `ajb_queue_items`, `ajb_played_songs`, `station_feedbacks`.
- App-level two-way scaffold exists but is not wired: `sync_changes` change-log
  (only `song`/`album`/`artist`/`genre` emit `SyncChange`, none of the new
  models), `slave_keys`/`jukebox_keys` (random `key_hash` node auth),
  `conflict_logs`, `PowerSyncService` (jukebox app, commented-out initializer).
  UUID PKs everywhere are the "random key" that makes multi-master collision-free.

### 7. Other design items (see `reference/UI_DESIGN_PASS.md`, not built)
Devices/sites model, unified Now Playing, mood search (dial filters + chips +
CLAP-text sidecar), expandable song rows in search, cover-art download
(coverartarchive.org/release/<mbid>/front-500; 8,439 releases have front art in
the mirror), importer fix + dropbox intake (`library_tools/IMPORTER_FIX_PLAN.md`),
headless tagger worker, library dedup.

## Known debt (as of the 2026-11-25 cleanup pass)

Runs on Ruby 3.4.13 and Rails 8.1 since 2026-11-25 (was 3.2.5 / 8.0.2, both past end of support).
`config.load_defaults` is still 8.0: adopting the 8.1 defaults is a separate, deliberate step.


- **Leftovers of the retired standalone jukeboxes** (removed 2026-11-25; code at tag
  `pre-jukebox-removal`): the tables `sync_changes`, `slave_keys`, `jukebox_keys`,
  `conflict_logs` (all empty) and `song_ratings` (5 rows, superseded by `station_feedbacks`), and
  the publication `pub_archive`. Nothing in the app reads or writes them; they can be dropped in
  a later migration. Postgres still runs with `wal_level=logical`, which is harmless.
- **Reference docs are unreviewed** (see `docs/README.md`): moved and indexed, not checked
  against the code.

## Dev / staging harness (gameforge)
- `library_tools/staging/` scripts run a production-copy of the app locally:
  `setup.sh`, `web.sh` (prod-mode web on 127.0.0.1:3909), `rails.sh`, `psql.sh`,
  `test.sh`, `station_e2e.sh`, `server_player_e2e.sh`. Containers: `archive-staging-{db,redis,web}`.
  Secrets/dump live in `~/archive-staging/` (outside the repo).
- Read-only prod DB clone login for pulling a fresh dump: role `archive_clone`
  on `192.168.17.109:5432` db `archive_production` (see `~/archive-clone.env`).

## Gotchas learned this session (save future-you time)
- **`module Archive`**: the app's top-level namespace is `Archive`, so an
  ActiveRecord model can't be named `Archive` — it resolves to the module. Use
  `ArchiveNode`.
- **Private-method action trap**: a controller action defined below `private`
  (or before a later `public`) raises `AbstractController::ActionNotFound` and
  the route 404s even though `recognize_path` matches. `JukeboxesController` has
  a `public` re-opener near `player`/`guest`; put new web actions there.
- **Per-form CSRF tokens** are on (Rails default): a token scraped from the wrong
  form on a page is rejected (422). Scope the token to the form you're posting.
- **schema_format is `:sql`** — `db/structure.sql` is the tracked source of truth
  (it IS committed and builds from scratch cleanly). Regenerate it after adding
  migrations: load committed `structure.sql` into an empty DB, `db:migrate`, then
  `db:schema:dump`. `library_tools/staging/*` delete the stray `db/schema.rb`.
- **Deploy**: `cd archive && kamal deploy` builds from the local tree; migrations
  do NOT run automatically — `kamal app exec --reuse "bin/rails db:migrate"`
  (the `--reuse` matters; without it a new container fights for port 3000). Back
  up first (`archive/KAMAL_DEPLOY.md`). Brief 502s on app swap.
