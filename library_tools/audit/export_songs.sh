#!/usr/bin/env bash
# Writes $AUDIT_DIR/songs.csv: one row per song with its stored file, from the production database,
# through the read-only archive_clone role (credentials in ~/archive-clone.env). Nothing is written to production.
set -euo pipefail
AUDIT_DIR=${AUDIT_DIR:-$HOME/archive-audit}
mkdir -p "$AUDIT_DIR"
set -a; . ~/archive-clone.env; set +a
docker run --rm -i --network host -e PGPASSWORD -e PGUSER -e PGCLIENTENCODING=UTF8 postgres:15 \
  psql -h "${PGHOST:-192.168.17.109}" -d archive_production -v ON_ERROR_STOP=1 -q <<'SQL' > "$AUDIT_DIR/songs.csv.tmp"
copy (
  select b.key, s.id as song_id, b.checksum, b.byte_size, s.file_format, s.duration,
         s.title, coalesce(s.artist_credit, a.name) as artist, s.artist_id, al.title as album, s.album_id,
         s.track_number, s.disc_number, s.musicbrainz_recording_id, s.created_at, s.original_filename,
         (select count(*) from ajb_played_songs p where p.song_id = s.id) as plays,
         (select count(*) from station_feedbacks f where f.song_id = s.id and f.kind = 'down') as downs
  from songs s
  join active_storage_attachments at on at.record_type = 'Song' and at.record_id = s.id and at.name = 'audio_file'
  join active_storage_blobs b on b.id = at.blob_id
  left join artists a on a.id = s.artist_id
  left join albums al on al.id = s.album_id
  order by b.key
) to stdout with csv header;
SQL
mv "$AUDIT_DIR/songs.csv.tmp" "$AUDIT_DIR/songs.csv"
echo "$(($(wc -l < "$AUDIT_DIR/songs.csv") - 1)) songs -> $AUDIT_DIR/songs.csv"
