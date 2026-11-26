# Archive player

The part of the archive that makes sound on a node's speakers. Two containers:

| Container | What it is |
|---|---|
| **daemon** (`station.py`, this directory's image) | Polls the archive every 2 s: which jukebox has the speakers, and should it play, pause or stop? Asks the archive for songs, hands OwnTone play links, reports now-playing back. Carries out skip / volume / speaker commands from the archive's remote-control page. |
| **OwnTone** | The AirPlay engine. Needs the host network (speaker discovery, timing). |

The daemon never listens for the archive; it only calls out, so the archive (and its `/player`
remote page, guests' phones, the station pages) control it from anywhere without the node being
reachable. It signs in with the node's **player token** (archive → Settings → Speakers) and may
then play whichever jukebox is put on the speakers. If it restarts mid-song (a deploy), it carries
on with what OwnTone is already playing.

## Deploy with Kamal (bigballs)

Kamal runs the daemon as the app and OwnTone as an accessory, both from `config/deploy.yml`. They
are two containers because a Kamal app cannot use host networking and OwnTone must.

One-time, on the deploying machine:

1. `~/.config/archive/player.env` (chmod 600):
   ```sh
   export NODE_TOKEN=...            # archive -> Settings -> Speakers
   export ARCHIVE_EMAIL=...         # optional: only for the daemon's own control page (search, station list)
   export ARCHIVE_PASSWORD=...
   ```
2. The GHCR token at `/home/sauce/secrets/jeedata/ghcr.env` (same as the archive deploy).

First cutover from the hand-run compose containers on bigballs (`owntone`, `archive-station`):

```sh
cd ~/src/archive2/station
ssh cayuse@192.168.17.109 'docker stop owntone'     # frees the host ports; kept for rollback
kamal accessory boot owntone                        # OwnTone, with the repo's ../owntone/owntone.conf and the existing ~cayuse/owntone/cache
kamal deploy                                        # builds + pushes the daemon; pre-app-boot stops archive-station
```

Every later deploy is just `kamal deploy` (daemon only; the music keeps playing).
OwnTone changes: `kamal accessory reboot owntone` (this does interrupt playback).

```sh
kamal logs                 # daemon log
kamal owntone-logs         # OwnTone log
kamal app details          # running container, health
```

Rollback to the old setup: `kamal app stop && kamal accessory stop owntone`, then on bigballs
`docker start owntone archive-station`.

Checks after a deploy: archive → Settings → Speakers shows the daemon **Online** with its speakers
listed; put a jukebox on the speakers and press Play on the remote.

## Without Kamal (another node, or by hand)

`cp .env.example .env`, fill in `ARCHIVE_URL` and `NODE_TOKEN`, then `docker compose up -d --build`.

## Settings (environment)

| Variable | Meaning |
|---|---|
| `ARCHIVE_URL` | The archive as this host sees it. Play links are built from this host name, and OwnTone must be able to fetch them. |
| `NODE_TOKEN` | The node's player token. Without it the daemon polls as `ARCHIVE_EMAIL` and plays only that account's jukeboxes. |
| `ARCHIVE_EMAIL` / `ARCHIVE_PASSWORD` | Optional account (DJ or above, with a local-playback grant) for the control page's search and station list. |
| `OWNTONE_URL` | OwnTone's JSON API. |
| `BIND_HOST` / `BIND_PORT` | Where the daemon's own control page listens. It has no login: LAN only. In the image it listens on 0.0.0.0 and the published port chooses the address. |
| `STATE_FILE` | Small JSON file (`/data` in the image) so a restart does not interrupt the music. |

`GET /up` is the health check (200 while the polling loop is alive).

## Testing

`library_tools/staging/server_player_e2e.sh` runs the whole thing against the staging archive and a
mock OwnTone (`test/mock_owntone.py`); `PLAYER_IMAGE=archive-player:dev` runs the container image
instead of the script.
