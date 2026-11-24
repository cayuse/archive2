#!/usr/bin/env bash
# One-off: generate the SongFileTag model + migration with the Rails generator.
set -euo pipefail
exec bundle exec rails g model SongFileTag \
  song:references \
  blob_key:string blob_checksum:string \
  container:string codec:string tag_format:string \
  bitrate:integer bitrate_mode:string sample_rate:integer channels:integer bits_per_sample:integer \
  duration_seconds:float \
  title:string artist:string album:string album_artist:string composer:string genre:string \
  track_number:integer track_total:integer disc_number:integer disc_total:integer \
  date_raw:string original_date_raw:string year:integer compilation:boolean \
  artist_sort:string album_artist_sort:string album_sort:string \
  label:string catalog_number:string barcode:string isrc:string asin:string media:string \
  release_type:string release_status:string release_country:string language:string script:string \
  bpm:float \
  musicbrainz_recording_id:uuid musicbrainz_release_id:uuid musicbrainz_release_group_id:uuid \
  musicbrainz_release_track_id:uuid musicbrainz_work_id:uuid \
  acoustid_id:uuid acoustid_fingerprint:text \
  has_cover_art:boolean has_lyrics:boolean \
  raw_tags:jsonb scan_error:text scanned_at:datetime \
  --no-fixture
