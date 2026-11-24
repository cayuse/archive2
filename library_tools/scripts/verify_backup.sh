#!/usr/bin/env bash
# Prove the shipped dump restores: pull it back from bigballs, restore into a scratch database
# in WSL's Postgres, count, drop.  Run as the WSL postgres user:
#   wsl -d Debian -u postgres -- bash verify_backup.sh
set -euo pipefail
F=/tmp/verify_archive_repaired.dump
SRC=/mnt/c/Users/cayuse/ai_stuff/music_archive/work/verify.dump
cp "$SRC" "$F"
dropdb --if-exists archive_restore_test
createdb archive_restore_test
pg_restore -d archive_restore_test --no-owner "$F" 2>&1 | grep -v -i "extension\|COMMENT\|errors ignored\|^$" | head -5 || true
psql -d archive_restore_test -At -F ' | ' <<'SQL'
select 'songs ' || count(*) from songs;
select 'albums ' || count(*) || ', with artist ' || count(artist_id) from albums;
select 'artists ' || count(*) from artists;
select 'song_file_tags ' || count(*) from song_file_tags;
select 'song_audio_features ' || count(*) from song_audio_features;
select 'song_neighbors ' || count(*) from song_neighbors;
select 'song_embeddings ' || count(*) from song_embeddings;
select 'genre_affinities ' || count(*) from genre_affinities;
select 'users ' || count(*) || ', playlists ' || (select count(*) from playlists) || ', jukeboxes ' || (select count(*) from jukeboxes) from users;
select 'migrations ' || count(*) || ', newest ' || max(version) from schema_migrations;
select 'publication tables ' || count(*) from pg_publication_tables where pubname = 'pub_archive';
select 'test accounts left behind ' || count(*) from users where email like '%example.invalid';
SQL
dropdb archive_restore_test
rm -f "$F" "$SRC"
echo "restore test database dropped"
