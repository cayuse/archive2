# Radio / Multi-peer Local Playback — status & unfinished business

Session handoff as of 2026-11-25. Written so this work can be picked up cold.

## What is DONE and DEPLOYED to production (master `9a93f20`)

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

### Production state right now
- Node row: `name="Home"`, `local_playback=true`, `player_url=nil`.
- Grants: **cayuse** (`cayuse@mac.com`) and **Katya** (`katerina.krasko@gmail.com`).
- Backup before deploy: `~/archive-backups/20261125-203625` on bigballs (dump +
  globals + SHA256SUMS). Rollback: `kamal rollback <ver>` or pg_restore.
- `station.py` on bigballs was NOT changed by this work.

## UNFINISHED — in rough priority order

### 1. Increment 2 — the durable `Station` (the big one, NOT started)
Today a "station" is a `Jukebox` (session prefix `station-`, `fill_mode: radio`)
and `StationFeedback` hangs off `jukebox_id` — node-local, so a station can't be
saved/propagated/resumed elsewhere. The refactor the owner asked for:
- New `Station` model: durable, user-owned, UUID PK, `origin_archive` stamp,
  holds seeds + tuning (intensity/variety/learn/requests_steer/genre/steer/
  kept_artists — currently in `jukeboxes.radio_settings` JSON).
- Re-point `StationFeedback` from `jukebox_id` → `station_id` so taste travels
  with the station, not the machine.
- `Jukebox` stays the node-local playback runtime; add `jukebox.station_id` to
  bind a runtime jukebox to a durable `Station` (radio OR classic "og" queue —
  both play styles).
- Adapt `StationTaste`, `SongRadio` (`for_jukebox`), `StationTuning` to take a
  `Station`. Update `stations_controller`, the api jukebox station actions, the
  station views, `station.py`, and the station tests.
- Old `station-` jukeboxes are disposable (owner said so) — no careful data
  migration needed.
- Hybrid asked for: a playlist can seed/inform a radio `Station`.
- Payoff ("save a station + its gathered data, resume it on another peer") is
  gated on sync, which is deferred (see #6). Build the model peer-safely now
  (UUID PKs already everywhere, origin stamp) without wiring sync.

### 2. Slice C remainder — make server-mode actually drive playback
The controller fork (IV) renders, but the *executor* for a server-played jukebox
is the node's hidden task. Remaining:
- Generalize `station.py` to drive ANY jukebox (classic queue or radio), not just
  personal stations.
- Handoff when the switch is flipped mid-play: hand current song+position between
  the browser player and the daemon. (Permutations the owner settled: toggle OFF
  while daemon playing → hand back to a browser player if one's open, else stop;
  one OwnTone per node = at most one jukebox "live on the speakers" at a time, so
  turning B on takes the speakers from A.)
- Optionally let the controller page issue transport (play/pause/skip/stop) to the
  daemon (CORS from the archive origin to the node daemon, or proxy via archive).
  MVP today is status + a link to the local player page.

### 3. Admin UI for the archive node (NOT built — owner will do later)
No UI to configure `ArchiveNode` (enable `local_playback`, set `name`,
`player_url`, `lan_cidr`). Currently set via console. Until there is one, enabling
a node and setting its player link is a `kamal app exec --reuse "bin/rails runner …"`.

### 4. `player_url` / local-player reachability
`player_url` is blank in prod. The station daemon binds `127.0.0.1:8337` on
bigballs (localhost-only) — not reachable from a browser as-is. Decide the real
local-player URL (expose the daemon on the LAN, or a reverse-proxied path) before
setting `player_url`, so the controller's "Open local player" link works.

### 5. AJB admin-code leak on `jukeboxes#show` (from the code review, NOT fixed)
`show` loads the jukebox unscoped and `ensure_owner` only guards edit/update/
destroy, so any moderator+ can open another host's jukebox page and read its
guest AND admin codes (Ed's change added the privileged admin code to what was
already leaking — guest code + `api_token` leak the same way). Fix: scope `show`
to `current_user.jukeboxes` or add `:show` to `ensure_owner`. Small; closes the
older leaks too. Also optional: a malformed `password` param (`?password[]=x`)
returns 500 instead of 401 in `Jukebox#guest_role_for` (`secure_compare` on a
non-String) — harden with `params[:password].to_s`.

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

### 7. Other design items (see `UI_DESIGN_PASS.md`, not built)
Devices/sites model, unified Now Playing, mood search (dial filters + chips +
CLAP-text sidecar), expandable song rows in search, cover-art download
(coverartarchive.org/release/<mbid>/front-500; 8,439 releases have front art in
the mirror), importer fix + dropbox intake (`library_tools/IMPORTER_FIX_PLAN.md`),
headless tagger worker, library dedup.

## Dev / staging harness (gameforge)
- `library_tools/staging/` scripts run a production-copy of the app locally:
  `setup.sh`, `web.sh` (prod-mode web on 127.0.0.1:3909), `rails.sh`, `psql.sh`,
  `test.sh`, `station_e2e.sh`. Containers: `archive-staging-{db,redis,web}`.
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
  up first (`KAMAL_DEPLOY.md`). Brief 502s on app swap.
