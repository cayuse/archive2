# Headless Jukebox → AirPlay 2: research notes

Date: 2026-11-24. Status: research only, nothing built. Goal: run a jukebox with no
browser and no local copy of the archive, and have its audio come out of AirPlay 2
speakers, driven from a Linux box (gameforge or bigballs), ideally in Docker.

## 1. What exists today (three playback paths)

| Path | Where it lives | Needs a copy of the archive? | Audio goes to |
|---|---|---|---|
| **Legacy jukebox app** | `jukebox/` + `player/` (mpv daemon) | **Yes**: Postgres logical replication (`pub_archive`, one slot per jukebox) plus a Syncthing copy of the files. This is the part you don't want any more. | Local sound card via mpv (or MPD in the older design) |
| **Archive Jukebox ("AJB")** | `archive/` (`Jukebox`, `AjbQueueItem`, `AjbPlayedSong`, `JukeboxPlaylistAssignment`), React player at `/jukeboxes/:id/player`, guest page, `ajb_design.md` | **No**: queue, history, auto-refill from assigned playlists, guest requests and heartbeat all live in the archive DB | The browser that has the player page open (Web Audio, crossfade) |
| **Signed play links** | `/s/:token` (`PublicSongsController`, `SongPlayToken`) | No | Anything that can fetch a URL (no login, no header, Range supported) |

The important finding: **the archive already contains the "sister jukebox"**. AJB has a
per-jukebox queue, refill from playlists, guest requests over ActionCable, and a
token-authenticated API that a non-browser player can use today:

- `POST /api/v1/auth/login` → encrypted Bearer token, 2 days by default, up to 30 days
  (`expires_in`), `POST /api/v1/auth/refresh` to roll it.
- `GET /api/v1/jukeboxes` → the user's jukeboxes (added recently for exactly this).
- `GET /api/v1/jukeboxes/:id/next_song` → atomically pops the head of the queue
  (refilling first if below `min_queue_length`), records it in `ajb_played_songs`, and
  returns `stream_url` / `download_url` plus title, artist, album, duration.
- `POST /api/v1/jukeboxes/:id/playback_status` → heartbeat (`current_song_id`,
  `position`, `is_playing`, `volume`, optional `event`/`diag`). The jukebox counts as
  "live" while this arrives at least every 30 s (`Jukebox::LIVE_WINDOW`); guests see
  now-playing via ActionCable broadcast.
- `GET /api/v1/songs/:id/stream` accepts the Bearer token **or** a browser session
  (`authenticate_media_request!`), supports Range.
- `/s/:token` gives a URL that needs **no header at all**, which matters when the thing
  fetching audio is a third-party engine such as OwnTone that cannot send Bearer tokens.
  There is currently no API endpoint that mints these; `SongPlayToken.generate` is only
  called from the song show page.

So the missing piece is not a new site. It is a **headless player**: a process that does
what the React player does (login, pick a jukebox, poll `next_song`, play `stream_url`,
send `playback_status`) but whose audio output is AirPlay 2 instead of a browser. The
existing `player/` daemon is already 80 % of that loop (Redis commands, mpv, status
hash); it just talks to the legacy jukebox API and plays to a sound card.

What this does **not** cover from the old jukebox app: nothing essential. The legacy app's
own queue, playlists, cached-song table and themes are duplicated by AJB. Deploying the old
jukebox onto bigballs with a shared DB (the option you floated) would work, but it keeps
the whole replica design alive for no benefit; AJB already is "jukebox with a shared DB".

## 2. The LAN right now

Probed via mDNS from both gameforge and bigballs (both on 192.168.16.0/23, same L2):

- **JBL Bar 1300** at 192.168.17.28 is the only AirPlay target. It advertises
  `_airplay._tcp` (AirPlay 2, features bit 38 "buffered audio" set, `flags=0x4`, no
  password/PIN flag), `_raop._tcp` (classic AirPlay 1, `et=0` = no encryption,
  `cn=0,1` PCM/ALAC, UDP) and `_googlecast._tcp`. It is the easiest possible target:
  AirPlay 1 senders work without pairing, AirPlay 2 senders work without HomeKit auth.
- **No HomePods, Apple TVs or Sonos were visible.** If any are planned, they change the
  answer: HomePod/Apple TV need HomeKit (HAP) pairing for native AirPlay 2, and Apple's
  OS 27.0 (Sept 2026) broke classic RAOP from third parties for about a month (fixed in
  27.2, but Apple TV still returned 403 to some senders as of late October). Betting on
  AirPlay 1 compatibility for Apple hardware is a liability in 2026.

gameforge: Debian 13, 22 cores, 30 GB, Docker 26, ffmpeg installed, PipeWire 1.4.2 running
headless for `cayuse` (linger on) with `module-raop-sink` and `module-raop-discover` present,
avahi-daemon **installed but inactive**. bigballs: 12 cores, 31 GB, avahi active.
Either host can do this; gameforge has nothing else on it that would fight for ports.

## 3. Ways to get audio from Linux to AirPlay 2 (survey, Nov 2026)

Sources and details are in the comparison below; the full survey is summarised here.

| Candidate | True AirPlay 2 (HAP pairing + PTP sync) | HomePod today | Docker | Control | Group sync, per-speaker volume | Maintained |
|---|---|---|---|---|---|---|
| **OwnTone 29.4** (ex forked-daapd) | Yes, PTP since 29.1 (Apr 2026), AirPlay 2 default | Works; HomePod mini 2 on 27.2 needs `ptp_disable` (issue #2063 open) | Official `owntone/owntone`, `network_mode: host`, runs its own avahi inside | JSON API :3689, websocket events :3688, MPD protocol | Yes / yes (`output_id`, `offset_ms`) | Active (release 2026-11-22) |
| **Music Assistant 2.7+** (engine: `cliairplay`) | Yes, most complete; weekly fixes | Works, actively fixed | Official image, host network mandatory | HTTP JSON + websocket, long-lived token, Python client | Yes / yes, per-device delay | Very active |
| **`cliairplay` standalone** (music-assistant/airplay-cli, GPL-3) | Yes | Works | Static binary; PTP needs UDP 319/320 (`CAP_NET_BIND_SERVICE`) | raw PCM on stdin + command pipe (`START_UNIX_MS`, `FLUSH`, `VOLUME`) | Yes via shared PTP daemon | Very active, but the contract is MA-internal |
| LMS (Lyrion) + AirPlay bridge | No, maintainer declined AirPlay 2 (Oct 2026) | Fragile (OS 27 saga) | Image, host net + D-Bus | Excellent CLI / JSON-RPC | LMS sync / yes | RAOP fixes only |
| pyatv | Compat only, single stream | Single stream works | pip | Python library | No | Active |
| **PipeWire `module-raop-sink` + mpv** | No (AirPlay 2 is an unmerged draft MR) | Hit-or-miss | DIY: headless pipewire + avahi | `pactl`/`wpctl` + mpv IPC (what `player/` already uses) | No | Active, AirPlay 1 only |
| node_airtunes2, lox node-airplay-sender, Python "openairplay" | No / best-effort | No | — | — | — | Dead or tiny |
| Snapcast, MPD | No AirPlay output at all | — | — | — | — | — |
| Roon, Audirvana | Yes | Yes | Proprietary servers | — | — | Commercial |

Key references: OwnTone JSON API (`POST /api/queue/items/add?uris=<http url>&clear=true&playback=start`,
`GET /api/player`, `PUT /api/outputs/set`, `PUT /api/player/volume?volume=N&output_id=ID`,
websocket topics `player`/`queue`/`outputs`/`volume`), OwnTone changelog 26.0 "non-library
URLs in the queue"; airplay-cli README; Music Assistant API docs (`POST /api` with
`{command,args}`, `/api-docs`); PipeWire raop-sink man page; LMS-Raop issue #57 (OS 27
breakage timeline); OwnTone issues #2042 (User-Agent 403 fix) and #2063 (mini 2 PTP).

## 4. Architecture options

### Option A (recommended): headless AJB player + OwnTone as the AirPlay engine

```
archive (bigballs, Kamal)                    gameforge (or bigballs), Docker host network
┌────────────────────────┐   Bearer API     ┌──────────────────┐  JSON :3689 / ws :3688  ┌──────────┐  AirPlay 2  ┌──────────┐
│ AJB queue / playlists  │◄────────────────►│ headless player  │◄───────────────────────►│ OwnTone  │────────────►│ JBL Bar  │
│ guests via ActionCable │  next_song,      │ (python, from    │  add URL, play, events  │ container│  (sync,     │ HomePod… │
│ /s/:token streams      │  playback_status │  player/)        │                         │          │  per-vol)   │          │
└────────────────────────┘                  └──────────────────┘                         └──────────┘             └──────────┘
```

- The player loop is the existing `player/player_logic.py` with two swaps: the API becomes
  the archive's AJB API, and mpv becomes OwnTone's JSON API. OwnTone does decoding,
  speaker discovery, pairing, multi-speaker sync and per-speaker volume. Rails never
  touches AirPlay.
- OwnTone fetches the audio itself, so it needs a URL that works with no header. Two
  choices: add an API endpoint (or a field on `next_song`) that returns a short-lived
  `/s/:token` URL for the popped song, or have the player download the file with its
  Bearer token into a directory OwnTone has as its library. The signed URL is simpler
  and the mechanism already exists.
- Track-end detection comes from the OwnTone websocket `player` event rather than polling;
  the player then pops the next song. To avoid gaps, keep one song queued ahead in
  OwnTone (pop `next_song` when the current one starts, not when it ends). Note this
  moves "played" bookkeeping one song early; AJB's `ajb_played_songs` is written at pop.
- **Loses crossfade.** OwnTone is gapless but has no crossfade; the AJB
  `crossfade_duration` setting would be ignored by this player. If crossfade matters,
  Option C is the one that can do it.
- Speaker selection and volume: expose OwnTone's outputs through the player's
  status/command channel so the archive UI (or a tiny page on the player) can pick
  speakers. Today the AJB UI has one volume; per-speaker volume would be new UI.
- Deployment: `owntone/owntone` container with `network_mode: host`, volumes for
  `/etc/owntone` (config, pairing state), `/var/cache/owntone`; the player as a second
  container (or systemd unit) on the same host. Kamal can run both as accessories or a
  plain compose file can, but **host networking is required** for mDNS and for PTP
  (UDP 319/320).

### Option B: Music Assistant as the engine

Same shape as A with Music Assistant in place of OwnTone. Strongest AirPlay 2 stack
(HomePod long-session sync, buffered streams, weekly fixes) and a token-protected API,
but it is a full music server with its own UI, Python 3.14, local files only via its
Filesystem provider, APIs still shifting, host networking mandatory. Fallback if
OwnTone misbehaves on specific Apple hardware.

### Option C: own daemon around `cliairplay` (maximum control)

Player decodes with ffmpeg → s16le PCM → one `cliairplay --protocol auto` process per
speaker, aligned with `START_UNIX_MS` and the shared `--ptp-daemon`. This is the only
option that can implement crossfade and the archive's exact queue semantics in our own
code, and it is a single static GPL-3 binary. Cost: we own gapless/flush/seek logic,
pairing storage, PCM mixing, and the stdin/command-pipe contract is documented as a
Music Assistant internal that changes often.

### Option D: quickest proof of concept, not the destination

PipeWire RAOP on gameforge with the existing mpv player: start `avahi-daemon`, load
`module-raop-discover`, the JBL appears as a PipeWire sink, point `player/` at it with
`--ao=pipewire` and a `PLAYER_API_URL` adapter for the AJB API. AirPlay 1 only, no
multi-speaker sync, not HomePod-safe, but a one-evening demonstration that the archive →
headless player → AirPlay loop works end to end on this LAN.

### Option E: old jukebox app on bigballs with the shared DB

Possible but keeps the replica-era code alive and still needs an AirPlay engine, so it
gains nothing over A. Not recommended.

## 5. What the archive would need (small)

1. An API way to mint a signed play URL for a song (new field on `next_song`, or
   `POST /api/v1/songs/:id/play_link`). Same `SongPlayToken`, short expiry (minutes to
   hours).
2. Optional: a "device player" flavour of `playback_status` that carries speaker list and
   per-speaker volume, so the AJB UI can show/select outputs. Not required for v1.
3. Optional: a way for the AJB UI to send commands (play/pause/skip/volume) to a headless
   player. Today commands flow browser-side; the `player/` daemon uses a Redis list. The
   archive already has Redis and ActionCable, so a per-jukebox command channel is a
   natural fit, but the first version can poll.

## 6. Suggested order of work

1. **Validate the engine on the JBL** (half a day): run `owntone/owntone` on gameforge with
   host networking, confirm it sees the bar, add a `/s/:token` URL to its queue, play,
   check volume control and that the websocket reports track changes. If HomePods are
   coming, borrow one for this step.
2. **Headless player v1**: fork `player/` into `player_ajb/` (or add a backend switch),
   AJB API client (login, jukebox pick, `next_song`, `playback_status`), OwnTone backend,
   queue-ahead of one song. Archive change from §5 item 1.
3. **Package**: compose or Kamal accessory definitions for OwnTone + player on gameforge,
   secrets for the archive login, runbook alongside `archive/KAMAL_DEPLOY.md`.
4. **UI**: speaker selection and per-speaker volume on the AJB jukebox page; commands via
   Redis/ActionCable.
5. Decide on crossfade: accept its loss, or move the output stage to Option C later. The
   player/engine boundary in step 2 is where that swap would happen, so keep it clean.

## 6a. Step 1 done: OwnTone validated on bigballs (2026-11-24)

Decision: AirPlay 2 with our own speaker groupings is a requirement, so OwnTone is the
engine. It now runs on bigballs (`owntone/` in this repo, `~/owntone` on bigballs, host
networking, web UI + JSON API on http://192.168.17.109:3689, websocket 3688).

- Discovery: OwnTone 29.4 listed the JBL Bar 1300 twice, as type "AirPlay 2" (ALAC) and
  as a Chromecast (Opus). No pairing or password needed.
- Playback: a signed `/s/:token` link (m4a, fetched by OwnTone from
  archive.cavaforge.net through the public IP, Range supported) played to the bar over
  AirPlay 2; `GET /api/player` progress advanced 10.02 s per 10 s wall clock. OwnTone read
  the tags from the stream (title, artist, album, year, track number), so the queue view
  is populated without any metadata from us.
- Per-output volume (`PUT /api/player/volume?volume=20&output_id=...`) and output
  selection (`PUT /api/outputs/set`) worked as documented.
- Future WiiM Pro class units are AirPlay 2 and Chromecast receivers, so they will appear
  in the same outputs list and can be grouped with the bar the same way.

## 8. The full jukebox app next to the archive on bigballs (shared DB + OwnTone)

Decision 2026-11-24: a headless player is not enough; the standalone `jukebox/` app
(search, browse, live page, playlists, themes, system player page) should run on bigballs
against the archive's own database and play through OwnTone.

### It is already built for this
- `config/application.rb` points migrations at `db/migrate_jukebox_only/`: five migrations
  that only create `jukebox_playlists`, `jukebox_playlist_songs`, `jukebox_queue_items`,
  `jukebox_cached_songs`, `jukebox_selected_playlists`, `jukebox_played_songs` and
  `system_settings` (`if_not_exists`). Every archive table (`songs`, `artists`, `albums`,
  `genres`, `playlists`, `users`, `active_storage_*`) is read in place, read-only models.
- `docker-compose.yml` already sets `DATABASE_URL` to `.../archive_production`, mounts
  the archive storage read-only at `/rails/storage`, and `resolve_local_audio_path`
  serves blobs straight off that mount; `jukebox_cached_songs` is only a fallback.
- Login is `User.find_by(email).authenticate` on the shared `users` table, so archive
  accounts work as-is.
- `GET /api/jukebox/player/stream/:id` needs no auth and sends the file inline, so OwnTone
  (host network on bigballs) can fetch `http://127.0.0.1:3001/api/jukebox/player/stream/<id>`.
- On bigballs today `archive_production` has none of the `jukebox_*` tables yet (only the
  sync-era `jukebox_keys`, `slave_keys`, `sync_changes`, `conflict_logs`), and both logical
  replication slots (`cayuse_jukebox_1`, `tindrum_jukebox_2`) are inactive.

### What to fix
1. **Shared-DB hygiene.** Run the five jukebox migrations once by hand against
   `archive_production` (they record into the shared `schema_migrations`; harmless, but
   archive's next `db:migrate` will dump jukebox tables into `archive/db/schema.rb`, so
   expect that diff). Remove `db:prepare` from `bin/docker-entrypoint` or gate it on an
   env var like the archive does, so a deploy can never migrate by accident.
2. **`system_settings` is the archive's table.** The jukebox writes `site_name`,
   `site_description`, `min_queue_length`, `refill_queue_to`, sync/rsync keys into it.
   Prefix jukebox keys (`jukebox_min_queue_length`) or give the jukebox its own table.
3. **Role enum.** Archive users have `dj: 3`; jukebox's `User` enum stops at `admin: 2`.
   Align it.
4. **Retire the replica machinery in this mode.** `PowerSyncService`, `archive_sync`
   pages, rsync settings, `jukebox_cached_songs` downloads: behind a `JUKEBOX_SHARED_DB`
   flag (hidden in the UI, jobs not scheduled) rather than deleted, in case a remote
   jukebox box ever comes back.
5. **Stream URLs for OwnTone.** `build_song_payload` builds `stream_url` from the app
   host; set it to the LAN address OwnTone can reach (`http://192.168.17.109:3001`) rather
   than the public vhost.
6. **Player: swap mpv for OwnTone.** Keep the Rails ↔ Redis ↔ player contract
   (`jukebox:commands`, `jukebox:player_status`, `jukebox:desired_state`) and the loop in
   `player/player/player_logic.py`; replace the `MPV` class with an `OwnTone` class with the
   same surface: `load(url)` = `POST /api/queue/items/add?uris=&clear=true&playback=start`,
   `pause/stop` = `PUT /api/player/pause|stop`, `get_prop` (idle/pause/time-pos/duration/
   volume) from `GET /api/player`, `set_volume` = `PUT /api/player/volume`. Later: keep one
   song queued ahead in OwnTone for gapless, and subscribe to the websocket instead of
   polling.
7. **Speaker UI in the jukebox.** New Rails endpoints that proxy OwnTone `/api/outputs`
   (list, select set, per-output volume) onto the `/system/player` page. This is the
   "my own groupings" feature. Pairing-required speakers (HomePod, Apple TV) would be
   paired once in OwnTone's own UI.

### Deploying it
- **Rails app via Kamal**, cloned from `archive/config/deploy.yml`: service `jukebox`,
  image `cayuse/jukebox`, host 192.168.17.109, `proxy: false`, `network: archive_default`,
  publish `3001:3001`, `DATABASE_URL` to `archive-db-1/archive_production`, Redis
  `redis://archive-redis-1:6379/2` (db 2, keeping the archive's db 1 separate), volume
  `/datatank/archive/psql_storage:/rails/storage:ro`, same `.kamal/` hooks with the
  service name changed (stop whatever holds :3001, detach from the `kamal` network), same
  secrets file plus the jukebox's own `RAILS_MASTER_KEY`.
- **nginx vhost** `jukebox.cavaforge.net` → `127.0.0.1:3001` with certbot, next to the
  archive vhost. The name is unused today.
- **OwnTone + player** stay in the `owntone/` compose on bigballs with host networking:
  add a `player` service built from `player/` (Python, no sound card, no mpv) with
  `PLAYER_API_URL=http://127.0.0.1:3001/api`, `PLAYER_REDIS_HOST=127.0.0.1`,
  `PLAYER_REDIS_DB=2`, `OWNTONE_URL=http://127.0.0.1:3689`. Redis port 6379 is already
  published on bigballs by the archive compose.
- Order: migrations by hand → `kamal deploy` from `jukebox/` → nginx vhost → player
  container → select playlists in the jukebox UI → play.

### Scope (clarified 2026-11-24)
This jukebox is the **house jukebox at the archive's site**: one instance, one global
queue, parties at home. Remote users keep using AJB in the browser; the two share songs
and playlists but not queues, and that is fine. bigballs has no sound hardware, so OwnTone
is the only audio path, and new endpoints (a WiiM outside, more bars) are just more
entries in OwnTone's outputs list that the jukebox's speaker panel can select and group.
No pairing-free speaker needs anything beyond being on the LAN.

## 9. Tagging incoming and untagged songs (researched 2026-11-24)

Problem: ~8,300 songs carry no MusicBrainz/AcoustID tags (the repair only used ids already in
the files), so duplicates of the same recording are invisible to everything but the audio
embedding, and the radio follows a song with its own duplicate. Uploads still go through
`AudioFileProcessingJob`, which reads five tags with ffprobe.

Can Picard do it programmatically? Not in a supported way as of Picard 3.0.5:
- `picard -e LOAD/CLUSTER/LOOKUP/SCAN/SAVE_MATCHED/QUIT` exists (since 2.9) but needs the GUI
  running; on a server that means `xvfb-run`, one slow launch per batch, no structured result.
- A headless core (`HeadlessTagger`, `picard-cli`) was merged upstream on 2026-11-01 and a
  `picard-cli shell` is in review for 3.1; nothing released yet. Worth re-checking in 2027.
- No Picard-as-library; no official Docker image (mikenye/picard is a VNC GUI).

What works headless today:
- **beets** 2.14 with the `chroma` + `musicbrainz` plugins: `beet import -qsC -l log file`,
  in place (`copy: no, move: no, write: yes`), auto-accepts strong matches only, album-aware
  in album mode. Skips are only visible in the log, not the exit code.
- **Custom worker**: `fpcalc` (libchromaprint-tools) → AcoustID lookup (free app key, 3 req/s)
  → pick recording by score and source count → MusicBrainz release lookup (1 req/s, proper
  User-Agent) → write tags with mutagen using Picard's tag mapping. The branch's
  `scan_tags.py` is already mutagen-based, so this is an extension of the existing scanner.
- SongKong (commercial, headless CLI) and a few album-folder watchers exist; not a fit.

Recommended shape: one `tagger` container (python + chromaprint + ffmpeg + mutagen +
pyacoustid) with a `tag <file> --json` entry point. Used by the upload job for each new file
and by a rake task for the 8,300 backlog. Accuracy expectation: recording/artist ids are
reliable for released music; album/date from a single-file match is a guess unless the
file's album tag confirms it, so keep album-level fields provisional.

Gotcha: rewriting tags in a file changes its bytes, and Active Storage keeps the blob
checksum. `blob.open` verifies it. So the worker must either write the tagged file back as a
new blob (replace the attachment) or update `active_storage_blobs.checksum`/`byte_size`
after the write. Never edit in `psql_storage` without doing one of those.

## 7. Open questions for you

- Which AirPlay receivers are actually in scope: just the JBL bar, or HomePods / Apple TV
  / Sonos too? This decides how much the AirPlay 2 pairing story matters.
- Is crossfade a must-have for the headless player? (Determines A vs C.)
- Host: gameforge is the cleaner choice (nothing else there, PipeWire and ffmpeg present,
  same /23 as the speakers); bigballs works too. Both need host networking for the
  AirPlay container.
- Should speaker control live in the archive UI (new AJB UI) or be acceptable in
  OwnTone's own web UI for v1?
