# OwnTone on bigballs (AirPlay 2 engine for the headless jukebox)

Background and the overall plan: `../HEADLESS_JUKEBOX_RESEARCH.md`.

- Runs as `cayuse` on bigballs in `~/owntone` (this directory copied there), image
  `docker.io/owntone/owntone:latest`, host networking.
- Web UI and JSON API: http://192.168.17.109:3689 (LAN only, `trusted_networks`).
  Event websocket: 3688. Both were free on bigballs; nothing else uses them.
- Volumes under `~/owntone`: `config/owntone.conf`, `cache/` (library DB, speaker
  pairing state), `media/` (empty; songs come in as signed archive URLs).

```bash
# update config or compose file
scp owntone.conf cayuse@192.168.17.109:owntone/config/
scp docker-compose.yml cayuse@192.168.17.109:owntone/
ssh cayuse@192.168.17.109 'cd ~/owntone && docker compose up -d'   # recreate if compose changed
ssh cayuse@192.168.17.109 'docker restart owntone'                   # config change only
ssh cayuse@192.168.17.109 'docker exec owntone tail -f /var/log/owntone.log'
```

## Driving it from the shell (what the headless player will do)

```bash
A=http://192.168.17.109:3689/api
curl $A/outputs                                   # speakers OwnTone sees (id, type, selected, volume)
curl -X PUT $A/outputs/set -H 'Content-Type: application/json' -d '{"outputs":["<id>","<id>"]}'
curl -X PUT "$A/player/volume?volume=20&output_id=<id>"   # per-speaker volume
curl -X POST "$A/queue/items/add?uris=https://archive.cavaforge.net/s/<token>&clear=true&playback=start"
curl $A/player                                    # state, item_id, item_progress_ms, item_length_ms
curl $A/queue
curl -X PUT $A/player/pause ; curl -X PUT $A/player/play ; curl -X PUT $A/player/next
```

Signed play links come from `SongPlayToken.generate(song_id, expires_in: ...)` in the
archive (`/s/:token`, no login needed, Range supported). Mint one for testing with
`kamal app exec --reuse 'bin/rails runner "..."'` from `archive/`.

Verified 2026-11-24: OwnTone 29.4 found the JBL Bar 1300 as "AirPlay 2" (and as a
Chromecast), queued a signed m4a link from the archive, and played it to the bar with
progress advancing in real time.
