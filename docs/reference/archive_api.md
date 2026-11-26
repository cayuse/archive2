# The Archive API

The JSON API under `/api/v1`. It serves the browser pages (the party-jukebox player, the guest
page, the station pages), the speaker daemon in `station/`, and the upload scripts in
`utilities/`. This document lists what the code implements. The source of truth is
`archive/config/routes.rb` and `archive/app/controllers/api/v1/`.

## Conventions

- All ids are UUID strings.
- Responses are JSON. Most carry `"success": true|false`; failures add `"message"`. The
  playlist endpoints are the exception: they use `"error"` / `"errors"` and their list and
  show responses have no `success` key.
- There is no rate limiting, no CORS configuration and no API for artists, albums, genres,
  users or search-as-a-resource. Song search is the `search` parameter of `GET /api/v1/songs`.
- A record that does not exist is handled by `ApplicationController`'s `RecordNotFound`
  handler, which redirects to `/` (HTML) rather than returning a JSON 404, except where an
  action rescues it itself (noted below).

## Authentication

There are four ways a request is authenticated, depending on the endpoint.

| Who | How | Used by |
|---|---|---|
| A user | `Authorization: Bearer <token>` | everything except the guest and health endpoints |
| A logged-in browser | the session cookie | `GET /api/v1/songs/:id`, `/download`, `/stream` only |
| The node's player daemon | `X-Node-Token: <archive_nodes.player_token>` | `/api/v1/jukeboxes/:id/...` and `/api/v1/node_player/sync` |
| A party guest | `password=<guest or admin code>` parameter | `/api/v1/guest/:jukebox_id/...` |

### The bearer token

The token is a JSON payload (`user_id`, `email`, `role`, `exp`, `iat`, `iss`) encrypted and
signed with `ActiveSupport::MessageEncryptor` using the app's `secret_key_base`, then Base64
(URL-safe) encoded. It cannot be forged or altered without the key. It is not stored, so
there is no per-token revocation; it stops working when it expires.

The web pages that call the API (stations, the jukebox player) mint a 2-day token for the
logged-in user server-side (`ApiTokenIssuer`), so they do not call `login`.

### POST /api/v1/auth/login

Parameters: `email`, `password`, optional `expires_in` (seconds; default 2 days, capped at
30 days).

```json
{
  "success": true,
  "message": "Authentication successful",
  "api_token": "…",
  "expires_at": 1795000000,
  "user": { "id": "6f0d9c2a-…", "name": "User Name", "email": "user@example.com", "role": "moderator" }
}
```

Wrong credentials: 401 `{ "success": false, "message": "Invalid email or password" }`.

### POST /api/v1/auth/refresh

Bearer token required. Returns a fresh `api_token` and `expires_at` (same `expires_in`
rule) plus `user`. The old token keeps working until it expires.

### GET /api/v1/auth/verify

Bearer token required. Returns `{ success, message, user }`.

### POST /api/v1/auth/logout

Bearer token required. Returns success and does nothing else; the token stays valid until
it expires. Clients just discard it.

### Token errors

401 with `message` one of `Missing API token`, `API token expired`, `Invalid API token`.

## Roles

`users.role` is `user`, `moderator`, `admin` or `dj`. In the API:

- any authenticated user can list, read, stream and download songs, and manage their own playlists;
- `moderator` and `admin` can upload (`bulk_upload`);
- `dj`, `moderator` and `admin` can host jukeboxes and stations (`User#can_host_jukebox?`);
- speaker playback also needs a playback grant on the node (`User#can_play_on?`).

## Songs

### GET /api/v1/songs

Bearer token. Parameters:

- `page` (default 1), `limit` (default 50, clamped to 1..100)
- `sort_by`: `created_at` (default), `title`, `duration`, `track_number`, `processing_status`
- `sort_order`: `asc` or `desc` (default `desc`)
- `search`: up to 10 whitespace-separated terms; every term must match the title, artist
  name, album title or genre name (case-insensitive substring)

```json
{
  "success": true,
  "songs": [
    { "id": "…", "title": "…", "artist": "…", "album": "…", "genre": "…", "duration": 180,
      "track_number": 1, "file_format": "mp3", "processing_status": "completed",
      "created_at": "2026-01-01T00:00:00.000Z" }
  ],
  "pagination": { "current_page": 1, "total_pages": 20, "total_count": 1000, "limit": 50 }
}
```

### GET /api/v1/songs/:id

Bearer token or browser session. Returns `song` with `id`, `title`, `artist`, `album`,
`genre` (names), `duration`, `file_format`, `file_size`, `download_url`, `stream_url`.
With `?include=binary` it returns the audio file itself instead.

### GET /api/v1/songs/:id/stream and /download

Bearer token or browser session. `stream` serves the audio inline and honours a `Range`
header (206 with `Content-Range`); `download` sends it as an attachment. Both answer 404
`This song has no audio file` when nothing is attached.

### GET /api/v1/songs/:id/radio

Bearer token. Songs that sound like this one.

- `count` (default 20, max 100)
- `exclude_ids` (array or comma-separated, first 500 used)
- `genre`: `any` (default), `adjacent`, `strict`
- a value from -1 to 1 for any of `energy`, `danceability`, `happiness`, `aggression`,
  `acousticness`, `electronic`, `instrumental`, `speech`

Returns `seed`, `analyzed` (whether the seed has audio features), `steer` and `songs`
(each with `id`, `title`, `artist`, `artist_id`, `album`, `album_id`, `genre`, `duration`,
`dials`). The caller's feedback on their first station is applied.

### POST /api/v1/songs/:id/rate

Bearer token. `value` = 1 (thumbs up), -1 (thumbs down) or 0 (clear). Kept for older
players; the thumb is recorded on the caller's first station. New clients use
`POST /api/v1/jukeboxes/:id/feedback`.

### POST /api/v1/songs/bulk_upload

Bearer token, moderator or admin (otherwise 403). Uploads **one** audio file per request,
as `multipart/form-data`:

- `audio_file` (required)
- `filename`, `title`, `artist_name`, `album_title`, `genre_name`, `track_number`, `duration` (optional)
- `skip_post_processing=true` to skip reading the file's tags

The title defaults to the file name. Unless skipped, tags are read with `ffprobe` during the
request and fill in whatever the parameters left blank. The song ends up `completed` (it has a
title and an artist), `needs_review`, or `failed`. Response is 201 with `song`
(`id`, `title`, `artist`, `album`, `genre`, `processing_status`, `created_at`); 422 when no
file was sent or the record is invalid; 500 with the error message on anything else.

## Audio files

An older pair of streaming endpoints, addressed by song id. Bearer token only (no session).

- `GET /api/v1/audio_files/:id` — `song_id`, `title`, `artist`, `album`, `duration`,
  `file_format`, `file_size`, `checksum` (Active Storage's Base64 MD5), `stream_url`, `download_url`
- `GET /api/v1/audio_files/:id/stream` — chunked, honours `Range`
- `GET /api/v1/audio_files/:id/download` — attachment

The playlist endpoints return these URLs; the jukebox endpoints return the
`/api/v1/songs/:id/stream` ones.

## Playlists

Bearer token. A user can list and read their own playlists and public ones. An admin's list
includes everyone's, but reading someone else's private playlist is still refused. Only the
owner can change a playlist or its songs; the owner or an admin can delete it. A refused
action is 403 `{ "success": false, "message": "Not authorized" }`.

| Endpoint | Parameters | Notes |
|---|---|---|
| `GET /api/v1/playlists` | `page`, `per_page` (default 20) | `playlists`, `pagination` (`current_page`, `total_pages`, `total_count`) |
| `GET /api/v1/playlists/:id` | | `playlist` with `songs` in order |
| `POST /api/v1/playlists` | `name` (required), `description`, `is_public`, `song_ids[]` | 201; creates it for the caller |
| `PATCH /api/v1/playlists/:id` | `name`, `description`, `is_public` | |
| `DELETE /api/v1/playlists/:id` | | |
| `POST /api/v1/playlists/:id/add_song` | `song_id`, optional `position` | |
| `POST /api/v1/playlists/:id/add_songs` | `song_ids[]` | appends in the given order, skips songs already present and unknown ids |
| `DELETE /api/v1/playlists/:id/remove_song` | `song_id` | 404 if the song is not in the playlist |
| `PUT /api/v1/playlists/:id/reorder_songs` | `song_order[]` (song ids in the new order) | |

A playlist is returned as `id`, `name`, `description`, `is_public`, `created_at`,
`updated_at`, `user` (`id`, `name`, `email`), `song_count`, and when songs are included,
`songs` (each with `id`, `title`, `track_number`, `duration`, `file_format`, `position`,
`artist`, `album`, `genre` as `{id, name|title}`, `audio_file_url`, `stream_url`).

## Jukeboxes and stations

A **party jukebox** is a queue that guests add requests to; it refills itself from its
playlists or by radio. A **station** is a personal radio; it is a `Station` record played
through a jukebox whose `session_id` starts with `station-`, and the API addresses it by
that jukebox's id. Both use the endpoints below.

All of these need a bearer token (or the node token, see "Speaker playback"). A jukebox is
only accessible to its owner: anyone else gets 403 `Access denied`. The collection
endpoints additionally require the DJ, moderator or admin role (403
`Not allowed to host a jukebox`), except `GET /api/v1/jukeboxes`.

### Collection

| Endpoint | What it does |
|---|---|
| `GET /api/v1/jukeboxes` | The caller's jukeboxes: `id`, `name`, `session_id`, `status`, crossfade settings, `auto_play`, `queue_count`, `playlists`. |
| `GET /api/v1/jukeboxes/stations` | The caller's stations (creating the first one, "My Station", if they have none). |
| `POST /api/v1/jukeboxes/station` | Open a station. No parameters: the first station. `station_id`: that one. `song_id`: restart it from that song. `new=true` with `song_id` and/or `playlist_id` (`playlist_mode` = `inspire` or `only`) and optional `name`: make a new station. A user can have 40. |
| `GET /api/v1/jukeboxes/shared_stations` | Every station someone has shared, with owner, seeds, playlists, thumb counts, how many copies exist and whether the caller has one. |
| `POST /api/v1/jukeboxes/copy_station` | `station_id` (a Station id from `shared_stations`), optional `name`: the caller's own copy. |

Station responses use the jukebox's `station_json`: `id`, `name`, `session_id`,
`fill_mode`, `station`, `guest_password`, `radio` (`genre`, `steer`, `intensity`,
`variety`, `learn`, `requests_steer`, `seeds`), `queue_length`, `live`, `server_playback`,
`transport`, `station_id`, `shared`, `name_edited`, `permanent`, `copied_from`, `playlists`.

### Station settings

| Endpoint | Parameters |
|---|---|
| `PATCH /api/v1/jukeboxes/:id/station` | `name` — rename (stations only) |
| `DELETE /api/v1/jukeboxes/:id/station` | remove the station and what it learned; the first station cannot be removed |
| `PATCH /api/v1/jukeboxes/:id/share` | `shared=true|false` |
| `PATCH /api/v1/jukeboxes/:id/radio_settings` | `genre` (`any`/`adjacent`/`strict`), `intensity` (-1..1 or `auto`), `variety` (0..1), `learn`, `requests_steer`, any dial (-1..1), `reset_steer=true` |
| `GET /api/v1/jukeboxes/:id/tuning` | everything that shapes the station, for the tuning page |
| `POST /api/v1/jukeboxes/:id/seeds` | `song_id` |
| `DELETE /api/v1/jukeboxes/:id/seeds/:song_id` | |
| `POST /api/v1/jukeboxes/:id/artists/:artist_id/keep` | put back an artist that thumbs-down removed |
| `POST /api/v1/jukeboxes/:id/feedback` | `song_id`, `kind` (`up`, `down`, `tired`, `never`, `clear`, `skip`, `finished`), optional `position`. `down`, `tired` and `never` also drop the song from the auto-filled queue and re-aim the station. |

### Queue and playback

| Endpoint | What it does |
|---|---|
| `GET /api/v1/jukeboxes/:id/status` | Name, status, crossfade settings, `server_playback`, `server` (the node's player state when on the speakers), `is_playing`, `current_position`, `current_song`. |
| `GET /api/v1/jukeboxes/:id/queue` | The queue: requested songs first, then auto-filled (`source` = `requested` or `random`), each with song details and stream/download URLs. |
| `GET /api/v1/jukeboxes/:id/current_song` | The head of the queue (not what is playing). |
| `GET /api/v1/jukeboxes/:id/next_song` | Tops the queue up if it is below `min_queue_length`, removes the head, records it in the play history and returns it with `stream_url`, `download_url` and `play_url` (a 12-hour `/s/:token` link that needs no header). 204 when there is nothing to play. |
| `GET /api/v1/jukeboxes/:id/playback_info` | What the player last reported. |
| `GET /api/v1/jukeboxes/:id/history` | `page`, `per_page` (default 25, max 100). Most recent first. |
| `POST /api/v1/jukeboxes/:id/queue` | `song_id`, optional `source` (default `requested`). 409 if it is already queued. |
| `DELETE /api/v1/jukeboxes/:id/queue/:song_id` | Remove a song. |
| `PATCH /api/v1/jukeboxes/:id/queue/:song_id` | `position` — move it. |
| `PATCH /api/v1/jukeboxes/:id/queue/:song_id/promote` | Turn an auto-filled song into a request. |
| `PATCH /api/v1/jukeboxes/:id/queue/:song_id/play_next` | Put it at the top. |
| `POST /api/v1/jukeboxes/:id/playback_status` | The player's heartbeat: `current_song_id`, `position`, `is_playing`, `volume`, optional `event` / `diag` (logged only). A jukebox is "live" while one arrived in the last 30 seconds. |

### Speaker playback

One jukebox at a time can play on the archive node's speakers, through the daemon in
`station/` (see `../../station/README.md`).

| Endpoint | What it does |
|---|---|
| `POST /api/v1/jukeboxes/:id/server_playback` | `on=true|false`, optional `transport` (`play`/`pause`/`stop`), `fresh=true`. Takes the speakers (from any other jukebox) or gives them back. Needs local playback enabled on the node and a playback grant; otherwise 403. |
| `POST /api/v1/jukeboxes/:id/transport` | `command` = `play`, `pause`, `stop` or `skip`, optional `quiet=true`. Only for a jukebox that is on the speakers. |
| `POST /api/v1/node_player/sync` | The daemon's poll (every 2 s): sends `state` (`outputs`, `volume`, `owntone_state`, `error`) and `ack`; gets `node`, the on-air `jukebox` (with a `resume` song and position) and pending `commands`. |
| `POST /api/v1/node_player/command` | A user with a playback grant: `cmd=volume` with `value` 0..100, or `cmd=output` with `id` and `selected`. |

The daemon sends `X-Node-Token` instead of a bearer token. With it, it may call the
`/api/v1/jukeboxes/:id/...` member endpoints for the jukebox that is on the speakers, acting
as that jukebox's owner; for any other jukebox it gets 403 `Not on the speakers`. Without a
node token configured, it can poll `sync` with a user's bearer token and is then only given
that user's jukebox.

## Guest endpoints

For the guest page of a party jukebox. No account: every request carries
`password=<code>`. The guest code gives the `guest` role, the admin code the `admin` role.
The jukebox must be live (a player has reported in the last 30 seconds), otherwise 403.
Errors: 400 no jukebox id, 404 unknown jukebox, 401 missing or wrong code, 403 admin code
required.

| Endpoint | Role | What it does |
|---|---|---|
| `GET /api/v1/guest/:jukebox_id/status` | guest | Jukebox name, status, the caller's `role`, playback state. |
| `GET /api/v1/guest/:jukebox_id/current_song` | guest | What is playing. No audio URLs are given to guests. |
| `GET /api/v1/guest/:jukebox_id/queue` | guest | The next 50 queue entries and `total_count`. |
| `GET /api/v1/guest/:jukebox_id/playback_info` | guest | Current song, position, volume, crossfade settings. |
| `GET /api/v1/guest/:jukebox_id/history` | guest | `page`, `per_page`. |
| `GET /api/v1/guest/:jukebox_id/search_songs` | guest | `q`, `page`, `per_page` (default 50). Same multi-term search as the song list. |
| `POST /api/v1/guest/:jukebox_id/request_song` | guest | `song_id`. `outcome` is `added`, `already_requested`, `already_queued`, or `bumped` (admin code, song was auto-filled). |
| `POST /api/v1/guest/:jukebox_id/promote_song` | admin | `song_id` — turn an auto-filled song into a request. |
| `DELETE /api/v1/guest/:jukebox_id/queue/:song_id` | admin | Remove a song. |
| `POST /api/v1/guest/:jukebox_id/player_command` | admin | `command` = `play`, `pause` or `skip`. Relayed to the host's browser player over the cable, or applied to the speakers when the jukebox is on them. |
| `GET /api/v1/guest/:jukebox_id/test` | guest | Debug endpoint. |

## Live updates (ActionCable)

`/cable`, channel `JukeboxChannel`, subscribed with `jukebox_id` (the UUID). The connection
is not authenticated. Messages are JSON with a `type`:

- `queue_update` — the queue changed; re-fetch it
- `playback_status_update` — `data` holds `current_song`, `position`, `is_playing`, `volume`, `crossfade_duration`, `timestamp`
- `player_command` — `command` = `play`/`pause`/`skip`, for the host's browser player

## Other endpoints

- `GET /api/v1/health` — no authentication. `{ status, timestamp, checks: { database, storage, search }, version }`; 503 when a check fails.
- `GET /s/:token` — not under `/api/v1`. Streams one song with no login, given a signed,
  expiring token (`SongPlayToken`). Honours `Range`. The song page makes these links, and
  `next_song` and `node_player/sync` return one as `play_url`.
- `GET /up` — Rails' own health check.
