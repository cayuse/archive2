# Peers: running more than one archive

A **peer** is another copy of The Archive on another machine (another house, a friend's place,
a laptop). Peers share one library and one set of people: a song dropped into any peer, a playlist
made on any peer, a thumb given to a station on any peer, shows up on all of them within seconds.
Music files follow within minutes. Each peer keeps running when the others are unreachable and
catches up when they are back.

This is the end-to-end playbook. It was worked out and run on 2026-11-26 with gameforge as the
peer and a copy of production standing in for bigballs (see "What has been tested"). Production
itself has not been converted yet: step 2 is the first step that touches bigballs.

## How it works

| What | How it travels | Notes |
|---|---|---|
| Library, people, playlists, stations, themes (the **shared** tables) | pglogical (Postgres logical replication), both ways, continuously | the list is `PeerSync::SHARED_TABLES` |
| Jukeboxes and their queues, node settings, Drop Box history, analysis keys, speakers (the **local** tables) | not at all: each peer has its own | `PeerSync::LOCAL_TABLES` |
| Music files | each peer pulls new files from the others every 5 minutes (`archive-sync-files`, rsync) | files are never changed or deleted, so pulling the union is always safe |
| Code and schema | every peer is deployed with Kamal from the same repository | every peer must be migrated before code that needs the migration (see "Releases") |

- **Conflicts.** If the same row is changed on two peers before they hear from each other, the
  most recent change wins, on every peer (`pglogical.conflict_resolution = last_update_wins`,
  which uses commit timestamps). pglogical writes a `CONFLICT:` line to the Postgres log each time.
- **The same thing created twice.** Genres (unique by name), and artists and albums with
  MusicBrainz ids, get ids derived from those keys (`NaturalId`), so two peers that import the same
  album while apart create the same rows and the clash is settled row by row. Without that,
  pglogical "settles" a clash on a unique key by swapping one peer's row for the other's, and
  whatever pointed at the swapped-out id points at nothing. `rake peer:status` reports dangling
  references.
- **No loops.** Each peer subscribes to the others with `forward_origins = '{}'`: it passes on
  only what was written locally, never what it received.
- **The network.** Peers talk to each other over a private network: WireGuard between the routers,
  so every peer has a private address (below, `PEER_WG`; bigballs `BB_WG`). Replication (Postgres)
  and file pulls (SSH) use only those addresses. People reach a peer however suits it
  ("Reaching a peer").

### Shared or local: deciding for a new table

Every table must be in one of the two lists in `archive/app/models/peer_sync.rb`; a test fails
otherwise. Shared: anything that describes the library or belongs to a person. Local: anything
about this machine or happening live on it. A shared table must not depend on rows of a local table
(replication applies rows without checking foreign keys).

## What runs where

| | bigballs (production) | a peer |
|---|---|---|
| App, Drop Box worker | Kamal, `config/deploy.yml` | Kamal, `config/deploy.peer.yml` + `config/deploy.peer.<peer>.yml` |
| Postgres | docker compose service `db` (container `archive-db-1`) | Kamal accessory `archive-db` |
| Postgres image | `ghcr.io/cayuse/archive-postgres:15-pglogical` (built from `deploy/postgres/Dockerfile`) | the same |
| Redis | compose `archive-redis-1` | Kamal accessory `archive-redis` |
| Web front | host nginx → `127.0.0.1:3000` | kamal-proxy (zero-downtime deploys), reached as the peer needs |
| Music files | `/datatank/archive/psql_storage` | `/srv/archive/storage` |
| Secrets (on the deploying machine) | `~/.config/archive/production.env` | `~/.config/archive/peers/<peer>.env` |

The deploying machine is gameforge for all of them (any machine on the private network with the
repository, Kamal, and the secrets files works).

## 0. Before you start

- WireGuard up between the routers; from the deploying machine you can `ssh` to the peer's
  private address, and the peer and bigballs can reach each other's private addresses.
- Docker installed on the peer host; `python3` and `rsync` 3.2.4+ (for `rrsync`) on every host.
- A backup of production (`archive/KAMAL_DEPLOY.md`, "Backup") before step 2.
- Postgres major version: production and every peer run **15**. Change it everywhere together.

## 1. Hosts: accounts, directories, file sync

Run `deploy/peer/host-setup.sh` **as root** on every host taking part (each new peer, and
bigballs). Copy the `deploy/peer` directory to the host first. It is safe to run again; run it a
second time once you have the other hosts' keys. It sets up:

| Account | What for | Notes |
|---|---|---|
| `archive` (`DEPLOY_USER`) | Kamal connects as it | in the `docker` group, so effectively root on that host: only the deploying machine's key |
| the owner of uid 1000 | owns the music files (the app container runs as uid 1000) and runs the file pulls | an existing account with uid 1000 is used (on bigballs: `cayuse`); otherwise `archive-data` is created |
| `archive-sync` (`SYNC_USER`) | other peers pull files through it | no password; its keys only allow `rrsync -ro <storage>`: read that directory, nothing else |

It also makes the directories (storage, intake, postgres, redis), a puller key for the file owner
(`~/.ssh/archive_sync_ed25519`), `/usr/local/bin/archive-sync-files`, `/etc/archive/file-peers`
(whom to pull from) and a cron job pulling every 5 minutes.

On a new peer:

```bash
sudo DEPLOY_KEY="$(cat gameforge-id_ed25519.pub)" sh deploy/peer/host-setup.sh
# note the puller key it prints
```

On bigballs (files stay where they are; no peer directories; Kamal already uses `sauce`):

```bash
sudo STORAGE_DIR=/datatank/archive/psql_storage SKIP_PEER_DIRS=1 DEPLOY_USER=sauce sh deploy/peer/host-setup.sh
```

Then exchange puller keys and tell each host whom to pull from (second run):

```bash
# on the peer: trust bigballs' puller, pull from bigballs
sudo PEER_KEYS=bigballs-puller.pub FILE_PEERS="archive-sync@BB_WG" sh deploy/peer/host-setup.sh
# on bigballs: trust the peer's puller, pull from the peer
sudo STORAGE_DIR=/datatank/archive/psql_storage SKIP_PEER_DIRS=1 DEPLOY_USER=sauce \
     PEER_KEYS=peer-puller.pub FILE_PEERS="archive-sync@PEER_WG" sh deploy/peer/host-setup.sh
```

Check from each side (as the file owner): `DRY_RUN=1 archive-sync-files <storage dir>` lists what
it would copy and copies nothing.

## 2. Convert bigballs' database (production change)

Production's Postgres becomes a pglogical node. About a minute of downtime while the database
restarts; the data directory is not touched. The new image is 15.20 (a minor upgrade from 15.14,
binary compatible; rehearsed on a 15.14 data directory).

```bash
# on bigballs, in ~/archive2/archive (the compose project); bring docker-compose.peer.yml there first
docker pull ghcr.io/cayuse/archive-postgres:15-pglogical
docker compose -f docker-compose.yml -f docker-compose.peer.yml up -d db     # recreates only archive-db-1
docker exec archive-db-1 psql -U postgres -d archive_production -c "show shared_preload_libraries"   # pglogical
```

The login peers replicate with (one password per deployment, `PEER_REPL_PASSWORD`, kept in each
peer's secrets file):

```bash
docker exec archive-db-1 psql -U postgres -d archive_production \
  -c "create role archive_peer login superuser replication password '<PEER_REPL_PASSWORD>'"
```

Make it a node. From the deploying machine, after deploying a release that contains `PeerSync`:

```bash
cd archive
kamal app exec "bin/rails peer:setup_node" --reuse --roles web \
  --env PEER_NAME:bigballs PEER_DSN:"postgresql://archive_peer:<PEER_REPL_PASSWORD>@BB_WG:5432/archive_production"
```

(`kamal app exec "<command>" ... --env KEY:value`: the command goes first, values are `key:value`,
DSNs as URIs because they cannot contain spaces there.)

Production publishes Postgres on every interface today (`5432:5432` in `docker-compose.yml`).
Peers only need the private address: change it to `"BB_WG:5432:5432"` (and keep `127.0.0.1`
for the read-only `archive_clone` login used by staging, if that is still wanted).

## 3. On the deploying machine: describe the peer

1. Secrets, `~/.config/archive/peers/<peer>.env`, chmod 600 (never in git):

   ```bash
   umask 077; cat > ~/.config/archive/peers/<peer>.env <<EOF
   export POSTGRES_PASSWORD=$(openssl rand -hex 24)
   export SECRET_KEY_BASE=$(openssl rand -hex 64)
   export PEER_REPL_PASSWORD=<the same as bigballs' archive_peer password>
   export MUSICBRAINZ_URL=<bigballs' read-only mirror URL over the private network, from production.env>
   EOF
   ```

   `RAILS_MASTER_KEY` and the mail settings come from `production.env` (the credentials file in
   the image is the same for every peer). `SECRET_KEY_BASE` is per peer: API tokens and sessions
   do not carry across peers; logins do (users are shared).

2. `config/deploy.peer.<peer>.yml`: copy `config/deploy.peer.example.yml`, set the hosts, the
   node name (`ARCHIVE_NODE_ID`: unique, never changed), paths, the database's private address,
   and one of the three ways of reaching it (next section).
3. `.kamal/peer-secrets.<peer>`: copy `.kamal/peer-secrets.example`, replace `example` with the
   peer's name.
4. `kamal config -c config/deploy.peer.yml -d <peer>` must print the config without errors.

## Reaching a peer

kamal-proxy runs on every peer; what differs is what stands in front of it. The overlay template
has all three (`config/deploy.peer.example.yml`):

| | When | Proxy settings | App settings |
|---|---|---|---|
| **A. Direct** | the peer has a public name and ports 80/443 | `host: <name>`, `ssl: true` (Let's Encrypt) | `APP_PROTOCOL https`, `FORCE_SSL`/`ASSUME_SSL` true |
| **B. Behind a proxy** | nginx/Caddy/the router holds the certificate (like bigballs today) | `host: <name>`, `ssl: false`, `forward_headers: true`, `run:` on a private port | the same as A; the outer proxy must send `X-Forwarded-Proto: https` |
| **C. Private only** | no name; reached over the private network | `ssl: false`, `run:` on `PEER_WG:<port>` | `APP_PROTOCOL http`, SSL flags false, `ALLOW_ALL_HOSTS true` (the gameforge test peer) |

kamal-proxy is one per host and shared by every Kamal app on it: its ports (`proxy.run`) are a
decision for the whole host.

## 4. Stand the peer up

```bash
cd archive
P="-c config/deploy.peer.yml -d <peer>"

kamal setup $P                     # db and redis accessories, kamal-proxy, the app and the Drop Box worker
kamal app exec "bin/rails db:schema:load" $P --roles web --env DISABLE_DATABASE_ENVIRONMENT_CHECK:1
```

The replication login and the node, on the peer's own database:

```bash
kamal accessory exec db --reuse "psql -U postgres -d archive_production -c \"create role archive_peer login superuser replication password '<PEER_REPL_PASSWORD>'\"" $P
kamal app exec "bin/rails peer:setup_node" $P --roles web --reuse \
  --env PEER_NAME:<peer> PEER_DSN:"postgresql://archive_peer:<PEER_REPL_PASSWORD>@PEER_WG:5432/archive_production"
```

Copy everything from bigballs, then listen to it (copy only into an empty peer, never both ways):

```bash
kamal app exec "bin/rails peer:subscribe" $P --roles web --reuse \
  --env SUBSCRIPTION:from_bigballs PROVIDER_DSN:"postgresql://archive_peer:<PEER_REPL_PASSWORD>@BB_WG:5432/archive_production" COPY:1
kamal app exec "bin/rails peer:wait" $P --roles web --reuse --env SUBSCRIPTION:from_bigballs
```

The peer's own settings (site name, theme), from bigballs, without bigballs' node id:

```bash
ssh bigballs "docker exec archive-db-1 psql -U postgres -d archive_production -At \
  -c \"copy (select * from system_settings where key <> 'archive_node_id') to stdout\"" \
| ssh archive@PEER_WG "docker exec -i archive-db psql -U postgres -d archive_production -c 'copy system_settings from stdin'"
```

Now bigballs listens to the peer (no copy: it already has everything):

```bash
kamal app exec "bin/rails peer:subscribe" --roles web --reuse \
  --env SUBSCRIPTION:from_<peer> PROVIDER_DSN:"postgresql://archive_peer:<PEER_REPL_PASSWORD>@PEER_WG:5432/archive_production"
```

Check both ends:

```bash
kamal peer                                   # bigballs: "receives from: <peer> ... replicating"
kamal peer $P                                # the peer: "receives from: bigballs ... replicating"
```

Each should list the other under "receives from" (replicating) and "read by" (behind: a few
bytes), and "dangling references: none".

With three or more peers, every peer subscribes to every other one (a full mesh: each change is
sent once by the peer it was made on, `forward_origins` stops it going round).

## 5. Files

The database is complete as soon as step 4 is done; the files arrive by `archive-sync-files`.
For a new peer the first pull is the whole library (467 GB, 74,724 files on 2026-11-26), so start
it by hand on the peer, as the file owner, where it can run for hours:

```bash
archive-sync-files /srv/archive/storage archive-sync@BB_WG        # resumable; BWLIMIT=20000 caps KB/s
```

Progress: `kamal app exec "bin/rails peer:files" $P --roles web --reuse` ("N of M files present").
After that, cron on each host pulls what is new every 5 minutes (`/var/log/archive-sync-files.log`).
Until a song's file has arrived on a peer, playing it there fails with "audio file missing";
everything else about the song is already there.

## Continued development

Development carries on as before: on gameforge, against staging, with the test suite. Nothing
there is a peer, so everything below changes nothing for day-to-day work. What changes is how a
release that touches shared tables reaches the peers.

### What goes wrong without care (seen on the test pair)

- **A node ahead of the others stops them.** A shared-table column that exists on one node and not
  on another stops the second node's subscription at the first row that carries it ("unknown column
  name"). pglogical does not restart it by itself.
- **A node behind the others undoes newer changes.** Replication sends whole rows. A node whose
  incoming replication is stopped, but which still takes writes, sends its stale copy of a row as
  the newest version; it overwrites the newer value everywhere, and when the stopped subscription
  resumes, the newer value is now "older" and is dropped. (Last-update-wins is per row: two peers
  editing different columns of the same row at the same moment also keep only one edit.)
- **A data migration run on every node runs N times.** Rows it creates (random ids) appear N
  times; updates are applied N times.

### The rules

1. **Schema of shared tables: `on_peers`.** bigballs is the *schema primary*
   (`PEER_SCHEMA_PRIMARY=true` in `config/deploy.yml`). Its migrations send shared-table changes
   through the replication stream (`pglogical.replicate_ddl_command`), so every node applies them
   at the same point, before any row that uses them. A new shared table is put in every node's
   replication set in the same step, so its rows replicate from the first one. On the other peers
   the block is skipped; where there are no peers it simply runs.

   ```ruby
   def up
     on_peers { add_column :playlists, :mood, :string }
     once_on_peers { Playlist.reset_column_information; Playlist.update_all(mood: "calm") }
     add_column :jukeboxes, :lights, :boolean        # a LOCAL table: as usual, on every node
   end

   def down
     on_peers { remove_column :playlists, :mood }
   end
   ```

2. **Data in shared tables: `once_on_peers`.** Runs on the schema primary only; the rows replicate.
3. **Local tables: as always.** Every node migrates its own.
4. **No renames of shared tables or columns.** During a release other peers still run the old code
   for a few minutes. Add the new column, copy (`once_on_peers`), move the code over, drop the old
   one in a later release.
5. **Expand, then contract.** A release must work against the schema of the release before it:
   new columns nullable or with a default; remove a column only once every peer runs code that no
   longer uses it.
6. **New tables**: classify them in `PeerSync` (a test fails otherwise).

`test/migrations_peer_rules_test.rb` checks every migration written after peers were introduced:
a shared table changed outside `on_peers`/`once_on_peers`, or renamed, fails CI. A deliberate
exception carries a comment saying why: `# peers: <reason>`.

### A release

1. Rehearse it on the gameforge pair if it has migrations: `bash library_tools/staging/peer_rehearsal.sh`
   migrates the stand-in (as schema primary) from the working tree, deploys and migrates the
   gameforge peer, and compares them; `peer_rehearsal.sh rollback` undoes it.
2. bigballs first: `kamal deploy`, then `kamal app exec --reuse "bin/rails db:migrate"`. Its
   shared-table changes go out to every peer through the stream.
3. `kamal peer` until every peer's reader shows `behind` near zero.
4. Each peer: `kamal deploy $P`, then `kamal app exec "bin/rails db:migrate" $P --roles web --reuse`
   (shared parts are skipped there: they already arrived).
5. `kamal peer` and `kamal peer $P`: the `schema:` fingerprint must be the same on every node,
   every subscription `replicating`.

A peer that is offline during a release catches up when it is back: its subscription waits (the
changes are kept for it, up to `max_slot_wal_keep_size`), it is deployed and migrated as in step 4,
and the schema changes it missed arrive in order. Deploy it before it takes writes, if you can.

Stopped subscriptions are restarted automatically: the Drop Box worker, which runs on every node,
tries every 2 minutes (`peer:heal` does it by hand). A subscription that keeps stopping has a cause
to fix: `kamal accessory logs db $P` / `docker logs archive-db-1` shows the error.

## Day to day

- `kamal peer` / `kamal peer $P`: node, schema fingerprint, subscriptions, how far behind each
  reader is, dangling references. `peer:files`: files present.
- Conflicts: `docker logs archive-db-1 2>&1 | grep CONFLICT` (bigballs), `kamal accessory logs db $P`.
  They are resolved; the log is for curiosity and for spotting something that keeps clashing.
- **Sound analysis**: run the analysis client against one peer only (bigballs); its results
  replicate. Two peers analysing the same songs would overwrite each other's work.
- **Speakers**: a peer with speakers runs its own player service (`station/`, its own Kamal
  config); speakers and jukeboxes are local to each peer.
- **A peer that is away for long**: each peer keeps the changes others have not collected, up to
  `max_slot_wal_keep_size` (50 GB). Past that, the waiting peer's slot is dropped (`wal=lost` in
  `peer:status`) and that peer must be re-seeded: let it send anything only it has (its readers
  show `behind` near zero), then on it drop the database (`kamal accessory remove db $P`, empty
  `/srv/archive/postgres`), and repeat step 4.

## Removing a peer

```bash
kamal app exec "bin/rails peer:unsubscribe" --roles web --reuse --env SUBSCRIPTION:from_<peer>      # on bigballs (and every other peer)
kamal app exec "bin/rails peer:unsubscribe" $P --roles web --reuse --env SUBSCRIPTION:from_bigballs
# on bigballs, the slot the peer read from, if it is still there:
docker exec archive-db-1 psql -U postgres -d archive_production -c "select pg_drop_replication_slot(slot_name) from pg_replication_slots where slot_name like '%<peer>%'"
kamal remove $P
```

Then take its line out of `/etc/archive/file-peers` and its key out of `archive-sync`'s
`authorized_keys` on the other hosts.

## Security

- Postgres and SSH between peers only on private (WireGuard) addresses. `archive_peer` is a
  superuser (pglogical needs it); its password is in each peer's secrets file only.
- File pulls: `archive-sync` can only read the storage directory (`rrsync -ro`); it cannot run
  commands, write, or leave the directory.
- `archive` (deploy) is in the docker group, which is root in all but name: only the deploying
  machine's key goes there.
- Secrets live in `~/.config/archive/` on the deploying machine, chmod 600, never in git.

## What has been tested (2026-11-26, on gameforge)

- A full peer deployed by Kamal from gameforge (`config/deploy.peer.gameforge.yml`, variant C on
  192.168.17.97:3920): app, Drop Box worker, pglogical Postgres and Redis accessories.
- A stand-in for bigballs (a pglogical Postgres loaded from the staging copy of production,
  `peer-sim-bigballs-db` on 192.168.17.97:5443), subscribed both ways with the peer: the initial
  copy (74,724 songs, 2.2 million sound-alike links, 74,655 embeddings) took about 20 s on one
  machine.
- Through the apps on each side: playlists made, renamed and deleted carried across both ways; a
  song dropped into the peer's Drop Box reached bigballs with its artist, album, genre, tags and
  file record; the same genre created on both sides while replication was paused became one row
  with one id; login, search and the Drop Box page on the peer.
- `host-setup.sh` as root on two throwaway Debian hosts with real SSH between them: accounts,
  directories, cron, and file pulls both ways with the right owner; the restricted key refuses
  commands, writing and paths outside the storage. (It found that `rrsync` needs `python3`.)
- File pulls between the real bigballs and gameforge as dry runs (no music copied): the key on
  bigballs is restricted the same way (`cayuse` standing in for `archive-sync`).
- Converting a Postgres 15.14 data directory to the 15.20 pglogical image.
- Continued development: a schema change made on one node only stopped the other's subscription,
  and a node writing while behind undid a newer change (why the rules exist); schema changes and
  new shared tables sent through the stream; a release with a shared-table migration rehearsed
  across the pair and rolled back (same fingerprint, data set once, replication never stopped);
  a stopped subscription restarted by the worker within 80 s once its cause was fixed.

Not tested: converting production itself (step 2), WireGuard between sites (all tests were on
one LAN), a full 467 GB seed, variants A and B of reaching a peer (configs validated only), and
more than two peers.

## Files

| File | What |
|---|---|
| `deploy/postgres/Dockerfile` | Postgres 15 + pglogical (`ghcr.io/cayuse/archive-postgres:15-pglogical`) |
| `deploy/peer/host-setup.sh` | root, per host: accounts, directories, file sync |
| `deploy/peer/sync-files.sh` | installed as `archive-sync-files`: pull new files from peers |
| `archive/docker-compose.peer.yml` | turns bigballs' compose `db` into a pglogical node |
| `archive/config/deploy.peer.yml` | Kamal base config for every peer |
| `archive/config/deploy.peer.example.yml` | template for a new peer, with the three ways of reaching it |
| `archive/config/deploy.peer.gameforge.yml` | the test peer |
| `archive/.kamal/peer-secrets-common`, `.kamal/peer-secrets.<peer>`, `.kamal/peer-hooks/` | peer secrets and hooks, apart from production's |
| `archive/app/models/peer_sync.rb`, `lib/tasks/peer.rake` | shared/local tables, `rake peer:*` |
| `archive/app/models/concerns/natural_id.rb` | ids derived from natural keys |
| `archive/lib/peer_migration.rb` | `on_peers` / `once_on_peers` for migrations |
| `archive/test/migrations_peer_rules_test.rb` | new migrations must follow the rules |
| `library_tools/staging/peer_rehearsal.sh` | rehearse a release on the gameforge pair |
