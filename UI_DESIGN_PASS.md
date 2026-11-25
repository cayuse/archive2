# Design pass: one jukebox UI, the house station inside the archive, mood search

Written 2026-11-25 against branch `feature/library-metadata` and the live system on
bigballs. This is a proposal; nothing here is built yet. Background on the house
station and OwnTone: `HEADLESS_JUKEBOX_RESEARCH.md`, `owntone/README.md`.

## Status

Built on this branch (2026-11-25), not yet deployed: **section 13** (per-station feedback, "sick
of this track", never-play, artist removal, taste vector, dial learning, skips and full plays as
signals, the intensity and variety flow) plus the near-duplicate guard and the guest-retune
setting from section 6, saved stations and the tuning page from section 10. Where it lives:

| Piece | Where |
|---|---|
| Feedback store | `station_feedbacks` table, `StationFeedback` (replaces `song_ratings`, whose rows are copied over) |
| What a station learned | `StationTaste` |
| Picking songs | `SongRadio` (seeds take turns, two-step neighbours, energy wave, duplicate guard) |
| Station settings | `Jukebox` (`radio_settings`: seeds, intensity, variety, learn, requests_steer, kept_artists) |
| API | `/api/v1/jukeboxes/stations`, `/station`, `/:id/feedback`, `/:id/tuning`, `/:id/seeds`, `/:id/artists/:id/keep` |
| Pages | `/stations` (list, new station from a song) and `/stations/:id` (tuning) |
| Players | thumbs / sick of it / never in the browser player; station picker, intensity and variety on the house station page |
| Checks | `archive/test/{models,services}`, `library_tools/scripts/station_engine_test.rb`, `library_tools/staging/station_e2e.sh` |

Differences from the text below: tempo is not part of the step limit (the tempo estimates are too
noisy); "why this song" is not shown in the queue; the global user layer (13.3) is only the
explicit never-play; guests' requests still seed a party radio, they just no longer drop the line-up.
Not built: sections 3 to 5, 9, 11 and 12 (devices and sites, the unified Now Playing page, mood
search, expandable song rows, cover art).

## 1. What exists today

Four separate surfaces drive the same jukebox data, each with a different look and a
different subset of features:

| Surface | Where | Stack | Has | Missing |
|---|---|---|---|---|
| Browser player (AJB) | `/jukeboxes/:id/player` | React (no build), Howler, own header | queue, guest QR, live updates | thumbs, mood dials, genre mode, search |
| House station page | `http://192.168.17.109:8337` | plain HTML served by `station.py` | thumbs, dials, genre mode, search, speakers, volume | archive theme, login, HTTPS, reachable only on the LAN by IP |
| Song radio page | `/songs/:id/radio` | Rails view | dials, genre mode, thumbs, add to playlist | not linked from song rows; "Play" always opens the browser player |
| Guest page | `/j/:code` | React (no build) | search, request, promote | mood browse; a guest request retunes the whole station |

Other facts that shape the design:

- The station daemon only makes outbound calls to the archive. It logs in with a real
  user's email and password from `~/station/.env`, and heartbeats every 10 s.
- The archive cannot send the station a command. Skip, stop, volume and speaker choice
  exist only on port 8337.
- Mood data covers the whole library: 74,655 of 74,687 songs have eight percentile dials
  (energy, danceability, happiness, aggression, acousticness, electronic, instrumental,
  speech), tempo, loudness, and a 512-dimension CLAP embedding
  (`laion/larger_clap_music_and_speech`, whose text encoder works).
- None of that is searchable. Song search is title/artist/album/genre `ILIKE` only, and
  it is implemented three times (web, API, guest).
- Taste data is nearly empty: 3 ratings, 449 recorded plays. Thumbs exist only on the
  station page and the radio page.
- Postgres 15 has `pg_trgm` but not `pgvector`.

## 2. Goals

1. One "Now Playing" UI in the archive that controls whichever player is live, browser
   or house speakers, with the same features either way.
2. The house station is a device the archive knows about, not a second app with its own
   page.
3. Mood is a first-class way to find music: filter, browse, free-text, and "start a
   station from this".
4. Every listen improves the station: thumbs, skips and requests are captured everywhere.

## 3. The house station becomes an archive "player device"

Keep `station.py` on bigballs (it has to sit next to OwnTone), but move its brain and
its UI into the archive.

**3.1 Command channel.** The station keeps polling; the archive answers with work.

- New table `jukebox_commands` (jukebox_id, kind, payload jsonb, created_at, taken_at).
  Kinds: `skip`, `stop`, `play`, `volume`, `set_outputs`, `output_volume`.
- New endpoint `GET /api/v1/jukeboxes/:id/commands?wait=20`: long-poll that returns
  pending commands and marks them taken. Latency is well under a second without opening
  any port on bigballs. With `queue_adapter: inline` and no job backend this stays plain
  request/response.
- The heartbeat grows a `device` block: speakers OwnTone can see (id, name, type,
  selected, volume), master volume, device name, software version. Stored on the jukebox
  as `device_state` jsonb and broadcast on the existing ActionCable channel.
- Drop the heartbeat to 5 s while playing so progress bars stay honest.

**3.2 Device identity instead of a password in a file.**

- New table `player_devices` (user_id, name, token_digest, last_seen_at).
- Pairing: the station shows a 6-character code on first start (log line and its fallback
  page); the user types it under Settings, Devices. The device then holds a long-lived
  token scoped to "play as this user's stations". No email or password on bigballs.
- A device belongs to a user, so "my station on the house speakers" follows whoever
  paired or claimed it. Hosts can hand the device to another host from the same page.

**3.3 Port 8337 shrinks** to a status and pairing page. All real control is in the
archive, behind login and HTTPS, and works from a phone off the LAN too.

## 4. One Now Playing UI

Rebuild the browser player view as the single player UI with a pluggable output:

- **Output picker ("Play on")** at the top: "This browser" (Howler, as now) or any live
  device ("House speakers"). Choosing a device turns the page into a remote; no audio
  plays locally. Under a device: speaker toggles with per-speaker volume, and saved
  speaker groups ("Living room", "Whole house", "Outside") stored in `device_state`.
- **Transport**: play/pause, skip, progress, volume. For a device these post commands;
  for the browser they act locally. Same buttons.
- **Tune panel** (new to the browser player, moved from the station page): thumbs up and
  down, genre mode (Any / Same and similar / Same only), the dial buttons, reset.
  Replace the fixed plus/minus 0.6 buttons with three-position toggles per dial
  (less / neutral / more) so the current tuning is visible at a glance.
- **Up next**: requested items first, then radio fill, each row showing why it was picked
  ("sounds like X", "requested by Y") plus remove and play-next.
- **Search and request** inline, with the mood filters from section 5.
- **Guest pane**: QR, short link, password, as now.

Build it in the same no-build React style under `public/javascripts/ajb`, splitting
`PlayerController` into a shared core plus `LocalOutput` (Howler) and `RemoteOutput`
(commands and device state). The guest page reuses the queue and search components.

**Across the rest of the archive:**

- A persistent mini bar in the main layout whenever one of your jukeboxes is live: title,
  artist, thumbs, skip, and a link to Now Playing. It reads the ActionCable channel, so
  it is the same for browser and house playback.
- Every song row (songs, album, artist, playlist, radio pages) gets one action menu:
  "Start station here", "Play next", "Request" (the last two only when something is
  live), "Similar songs". Today the radio page is only reachable from the song detail.
- Navigation: replace "Jukeboxes" with "Now Playing" (goes to your station, live or not)
  and move party-jukebox management under it. Fold "Upload Song", "Maintenance",
  "Manage Users" and "System Settings" into one admin menu; the top bar currently holds
  up to ten buttons.
- Theme: player and guest pages bring their own header and partly their own colours.
  Move them onto the `theme.css` variables so the theme switcher applies everywhere, and
  delete `theme.css.bak`.

## 5. Mood search

**5.1 One search service.** Extract the three copies of song search into
`SongSearch.new(scope, params)`. It accepts text terms plus filters and is used by the
web songs page, `/api/v1/songs`, and guest search.

**5.2 Filters from the dials (SQL only, ships first).**

- Params: `energy=0.6..1`, `happiness`, `danceability`, `acousticness`, `electronic`,
  `aggression`, `instrumental`, `speech`, `bpm=110..130`, `genre`, `rated=up`.
- Join `song_audio_features`; add indexes on the dials that lack one (only energy and
  speech are indexed). 75k rows is small either way.
- **Mood chips** as named presets over the dials, shown above search results and on the
  guest page:

  | Chip | Rule (percentiles) |
  |---|---|
  | Chill | energy < 0.35, aggression < 0.4 |
  | Upbeat | energy > 0.6, happiness > 0.6 |
  | Party | danceability > 0.7, energy > 0.6 |
  | Dark | happiness < 0.3 |
  | Heavy | aggression > 0.75, energy > 0.7 |
  | Acoustic | acousticness > 0.75 |
  | Electronic | electronic > 0.75 |
  | Focus | instrumental > 0.8, speech < 0.3, energy 0.2..0.6 |
  | Spoken | speech > 0.9 (comedy, audiobooks; also the way to exclude them) |

  Thresholds get tuned by ear once; they live in one Ruby constant.
- Song rows and the song page show the top two or three dials as small tags plus BPM, so
  the data is visible and people learn what the chips mean.
- Sort options: most energetic, mellowest, BPM, recently added, recently played.

**5.3 Free-text "sounds like" search (the CLAP text side).**

Typing "rainy sunday morning piano" or "angry fast guitars" is encoded by the CLAP text
tower and matched against the 74,655 song embeddings.

- A small sidecar on bigballs (`library_tools` already pins the model): loads the
  embeddings into one NumPy matrix (about 150 MB), runs the text encoder on CPU, and
  answers `GET /similar?q=...&n=200` with song ids and scores in tens of milliseconds.
  Brute force is fine at this size, so `pgvector` is not needed.
- The archive calls it from `SongSearch` when the query is flagged as a vibe (a toggle
  next to the search box: "Titles" / "Vibe"), then applies the normal filters and
  permissions to the returned ids. If the sidecar is down, the toggle is disabled and
  nothing else breaks.
- The same call powers **"Start a station from a description"**: take the top matches as
  the seed pool. This is the feature that makes the station feel new.
- New songs need an embedding before they are findable this way; that belongs with the
  tagger and intake work in `library_tools/IMPORTER_FIX_PLAN.md`.

## 6. Station behaviour worth fixing in the same pass

- **Near-duplicate guard** in `SongRadio#candidates`: skip neighbours scoring 0.99 or
  higher against anything recent, and anything whose normalized title and artist match a
  recent play. This is the "same song two tracks later" bug already diagnosed.
- **Guest requests should not retune a party.** `request_song` calls `retune!`
  unconditionally. Make it a jukebox setting, "Requests steer the station": on for a
  personal station, off by default for jukeboxes with guests.
- **Implicit taste.** Record skips (weak negative) and completed plays and requests
  (weak positive) alongside thumbs, and let `SongRadio#load_taste` use them at lower
  weight. Three ratings is not enough signal to matter today.
- **Saved stations.** A station already persists per user (queue, tuning, history), but
  there is only one. Add named presets: "save this tuning" stores seed, genre mode and
  dials; the Now Playing page lists them as one-tap starts.
- **Loudness levelling.** `loudness_db` is known per song. Send it with `next_song` and
  let the device trim OwnTone volume per track so quiet rips and loud masters match.
- **History page.** "Recently played" with thumbs and "start station here", per jukebox
  and per user. The data is already in `ajb_played_songs`.
- **Library dedup** (913 byte-identical groups) stays a separate job, but the search
  service should collapse exact duplicates in results meanwhile.

## 7. Suggested order

| Step | Work | Why this order |
|---|---|---|
| 1 | `SongSearch` service, dial filters, mood chips, dial tags on rows | SQL only, immediately usable, no device work |
| 2 | Radio duplicate guard, guest-retune setting | small, fixes behaviour noticed in daily use |
| 3 | Command channel, device state, tune panel and output picker in the player | the integration itself; 8337 becomes optional |
| 4 | Mini bar, song-row action menu, navigation and theme cleanup | builds on step 3's live state |
| 5 | Device pairing tokens | removes the password from bigballs |
| 6 | CLAP text sidecar, vibe search, station from description | new service to run; biggest payoff |
| 7 | Implicit taste, saved stations, loudness, history page | polish once the surfaces are unified |

## 8. Decisions made (owner, 2026-11-25)

- Guests keep title search on the request page as it is now. Anyone browsing the
  library while logged in gets every kind of search (text, mood chips, filters, vibe).
- Who may play on a site's speakers is decided by that site's owner (section 9).
- One stream per house is the normal case. The model allows more than one device per
  site, but the UI does not have to make two simultaneous streams easy.

## 9. Sites, users and devices (replaces 3.2)

The archive is multi-user and may be mirrored to other houses. "Play on the house
speakers" is therefore a permission tied to a place, not a global feature.

**Model**

- `sites`: a place with speakers. name ("Home", "Cousin's house"), owner_id. A mirrored
  install has its own site row; one install can also hold several.
- `site_members` (site_id, user_id, role: owner or player). The owner decides who may
  play locally. At home that is the owner and their spouse; at the cousin's house the
  cousin decides. Everyone else never sees the device in "Play on".
- `player_devices` (site_id, name, token_digest, last_seen_at, device_state jsonb,
  current_jukebox_id, allowed_outputs). A device is one station daemon plus its OwnTone.
  It pairs to a site, not to a user, so no personal password sits on the box.
- Speaker groups are saved per device ("Living room", "Whole house", "Outside"), and
  each site member can have a default group.
- Settings: site owners get a "Local playback" page (devices, members, speaker groups).
  Each user gets "Default output: this browser / <device>".

**Behaviour**

- A device plays one jukebox at a time. "Play on House speakers" from a member's Now
  Playing page points the device at that member's station.
- If the device is already playing someone else's station, the UI says whose and asks
  "Take over?" rather than silently switching. The other person's station is not lost;
  it is just no longer on the speakers, and they can take it back the same way.
- A second device on the same site (say, outside speakers on another OwnTone) appears as
  a second entry in "Play on", and can run a different station at the same time. This
  falls out of the model; nothing special is built for it.
- Now Playing is per user: the mini bar and the page show the stations *you* may
  control: your own (browser or device) and, for site members, whatever is on the site
  device.
- Browser playback stays available to any user allowed to host, anywhere, as today.

## 10. Stations saved per user, with an editable tuning

Today each user has exactly one station and its taste data is invisible. Change to:

- `stations` are jukebox rows owned by a user (as now), but a user may keep several, each
  with a name, seed songs, genre mode, dials and its own history. "My Station" is just
  the first.
- A **Tuning page** per station shows everything that shapes it, all editable:
  - Seeds: the songs it was started from. Add ("this is a cool one") or remove.
  - Liked: every thumbs-up, with remove. Disliked: every thumbs-down, with remove.
    This is where an accidental thumb gets undone.
  - Dials and genre mode, the same three-position toggles as Now Playing.
  - Recently played, with thumbs, so tuning after the fact is easy.
- Ratings stay global per user (a thumbs-down means "never play this for me" on every
  station), which is how `song_ratings` already works. Seeds and dials are per station.
- Starting a saved station on a device or in the browser is one tap from Now Playing.

## 11. Song rows: expand instead of cramming

The songs table currently puts a 180 by 25 pixel audio element in every row, which
leaves the scrubber and volume unusable.

- Rows go back to being compact: title, artist, album, length, one play button, one
  "more" chevron.
- Clicking or tapping a row expands a panel directly under it (one open at a time):
  cover art, a full-width audio player with every control usable, the mood tags and BPM,
  thumbs, and the actions (Start station here, Play next, Request, Similar songs, Add to
  playlist, Edit).
- The audio element is created only when the row is opened, so a page of 50 songs no
  longer builds 50 players.
- The same row component is used on the songs, album, artist, playlist and radio pages.

## 12. Cover art

Measured 2026-11-25:

| Fact | Count |
|---|---|
| Albums in the archive | 12,894 |
| Albums with a stored cover image | 0 |
| Albums with a MusicBrainz release id | 11,298 |
| Of those, releases with front cover art listed in the mirror | 8,439 |

- `Album` already has a `cover_image` attachment and a `cover_image_url` column; nothing
  fills them. The importer does not extract embedded pictures either.
- The MusicBrainz mirror on bigballs holds the Cover Art Archive *index* (which releases
  have art, which image is the front), not the image files. The images live at
  `https://coverartarchive.org/release/<release-mbid>/front-500`, a free public service.
- Plan, in order of yield:
  1. For the 8,439 albums: a throttled rake task downloads the 500 px front image and
     attaches it as `cover_image`. Stored locally, so playback pages never call out.
  2. For albums without a hit: try the release group's art (the mirror has
     `release_group_cover_art`), which covers other pressings of the same album.
  3. For the rest: extract the embedded picture from one of the album's files (mutagen
     or ffmpeg). This also belongs in the importer for new uploads.
- Art then appears in the expanded song row, Now Playing, the mini bar, album pages, and
  can be handed to OwnTone so AirPlay screens show it.

## 13. Station feedback and flow (owner decisions 2026-11-25; supersedes the taste parts of 6 and 10)

What `SongRadio` does today: thumbed-down songs never play (globally); neighbours of
downs are penalised and neighbours of ups boosted, saturating at three; an artist with
two more downs than ups takes a penalty. It ignores skips, has no per-station memory,
and has no shape: each pick is a weighted random choice near the seed and the last song.

**13.1 Feedback is per station (decided).**

- `station_feedback` (jukebox_id, user_id, song_id, kind, created_at, expires_at).
  Kinds: `up`, `down`, `tired`, `skip`, `finished`, `request`.
- `up` / `down` apply to the station they were given on. A down means "not on this
  station", nothing more.
- **"Sick of this track" (decided, taken from Pandora).** A third button next to the
  thumbs. It skips the song and shelves it for 30 days on every station of that user
  (`expires_at`), and never counts as dislike: no penalty to the artist or to
  similar-sounding songs. Shelved songs are listed on the tuning page with "bring back".
- Artist rule per station: two downs and no ups removes that artist from the station.
  Match on MusicBrainz artist id and `song_artist_credits`, not the artist row, so
  duplicate rows and featured credits are caught. Listed and reversible on the tuning
  page.
- Skips before 30 seconds are a weak negative, completed plays and requests a weak
  positive, at a fraction of a thumb's weight.
- Existing `song_ratings` rows (3 today) migrate to feedback on the owner's station.

**13.2 What the station learns from it.**

- A taste vector per station: mean of liked embeddings minus a fraction of the mean of
  disliked ones (Rocchio relevance feedback). Candidates are scored by similarity to it,
  replacing the neighbour count that saturates at three.
- Dial learning: when the dials of ups and downs differ consistently (say, downs are all
  high aggression), shift the station's dial targets and show the shift on the tuning
  page, where it can be reset.

**13.3 Global user preference (later, only when there is data).**

- Not built now. Once a user has enough feedback across stations (rough bar: a few
  hundred events over at least three stations), derive a user-level layer from what is
  consistent everywhere: artists removed on every station they appeared on, a global
  taste vector, dial leanings.
- It applies as a weak prior under each station's own feedback, never overriding it, and
  is visible and editable on a profile page. An explicit "never play this for me" action
  can exist from day one as the only global signal.

**13.4 Flow.** Two settings per station replace the ratcheting steer on energy:

- **Intensity** (mellow to high) sets the centre; **Variety** (steady to dynamic) sets
  the swing.
- The picker follows a slow wave of target energy over roughly ten songs (build, peak,
  release), scores candidates by distance from the target for their slot, and caps the
  energy and tempo step between neighbouring songs. Steady plus high stays hard
  throughout; steady plus mellow stays soft.
- Grounding: radio scheduling rules (energy and tempo separation), Pampalk, Pohle and
  Widmer 2005 on skip-driven playlists, Flexer et al. 2008 on smooth paths between songs,
  Bonnin and Jannach 2014 survey. Cited from memory; no single "correct" arc exists, so
  the wave length and step cap are tuned by ear.
