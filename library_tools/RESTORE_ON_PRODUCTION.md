# Repaired archive database

Made 2026-11-24 from a copy of `archive_production` taken that morning, after the metadata rebuild
and the audio analysis. Code that goes with it: branch `feature/library-metadata` of
`cayuse/archive2` (commit a94cbb0 or later). **The database and the code must go live together**:
the dump has 12 migrations the old code does not know about, and the new code needs them.

| File | What it is |
|---|---|
| `archive_repaired_<stamp>.dump` | Complete database (`pg_dump -Fc`, no owners). Everything: users, playlists, jukeboxes, repaired songs / artists / albums / genres, tags, radio data. |
| `replay_data_<stamp>.tar.gz` | The inputs to rebuild the same result with rake tasks instead of restoring the dump. |
| `SHA256SUMS` | Checksums. |

When the dump was made, live had not changed since the copy was taken (last activity 2026-10-03:
same counts of users, playlists, jukeboxes, queue and play history). If the site has been used since,
restoring the dump loses that activity; use Option B instead.

## Option A: restore the dump (simple; old database kept for rollback)

On bigballs. Step 1 does not touch the live database and can be done any time.

```sh
cd /datatank/downloads/archive_repaired_backup && sha256sum -c SHA256SUMS

# 1. load into a NEW database next to the live one
docker exec archive-db-1 createdb -U postgres archive_repaired
docker exec -i archive-db-1 pg_restore -U postgres -d archive_repaired --no-owner < archive_repaired_*.dump
docker exec archive-db-1 psql -U postgres -d archive_repaired -c \
  "select (select count(*) from songs) songs, (select count(*) from albums) albums, (select count(*) from song_neighbors) neighbours"
#    expect 74687 songs, 12894 albums, 2194370 neighbours

# 2. cut over: stop the site, swap the names, deploy the new code, start the site
#    (stop the archive web container first so nothing is connected)
docker exec archive-db-1 psql -U postgres -c "ALTER DATABASE archive_production RENAME TO archive_production_before_repair"
docker exec archive-db-1 psql -U postgres -c "ALTER DATABASE archive_repaired RENAME TO archive_production"
#    then deploy feature/library-metadata with Kamal. db:migrate will find nothing to do.

# rollback: stop the site, rename the two databases back, redeploy the old code.
```

Notes:
- `pg_restore` prints a few "must be owner of extension" style warnings for comments; they are harmless.
- Replication: live has 2 replication slots, both inactive, and the publication `pub_archive`
  (15 tables). The slots stay with the old (renamed) database. The dump recreates `pub_archive` in
  the new one, without the new tables. Jukebox machines that subscribe will need the new migrations
  and a fresh subscription before they sync again.
- Audio files are not in the dump and do not move; the blob keys are unchanged.

## Option B: replay on the live database (keeps anything that happened on live since)

After deploying the new code (which runs the migrations), from the app container, with the tarball
unpacked somewhere the container can read (shown here as `/data`):

```sh
bin/rails 'library:import_file_tags[/data/tags.jsonl]'      # tags read from the files
DRY_RUN=1 bin/rails 'library:rebuild[/data/mb]'              # prints what it would change, then rolls back
bin/rails 'library:rebuild[/data/mb]'                        # artists / albums / genres / credits
bin/rails 'library:import_audio[/data/audio/out]'            # dials, sound-alike links, vectors, genre adjacency
```

The rebuild runs in one transaction and writes no `SyncChange` rows.
`audio/errors.jsonl` lists the 32 songs whose audio could not be decoded (candidates for re-ripping).

## Afterwards

- Headless player: `station/` in the repo (`cp .env.example .env`, fill in an account, `docker compose up -d`),
  control page on `http://192.168.17.109:8337`.
- Safe to delete once you are happy: `/datatank/downloads/archive_audio_scratch` (ZFS clones used for the
  analysis; they take no real space).
