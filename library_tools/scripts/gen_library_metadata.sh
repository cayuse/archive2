#!/usr/bin/env bash
# One-off: generate the library-metadata migrations and the SongArtistCredit model with the Rails generators.
# Run:  bash rails.sh bash /work/scripts/gen_library_metadata.sh
set -euo pipefail

bundle exec rails g migration AddMusicbrainzFieldsToArtists \
  musicbrainz_id:uuid:uniq sort_name:string disambiguation:string artist_type:string

sleep 1
bundle exec rails g migration AddReleaseFieldsToAlbums \
  musicbrainz_release_id:uuid:uniq musicbrainz_release_group_id:uuid:index \
  artist_credit:string sort_title:string \
  release_year:integer original_release_year:integer \
  release_type:string secondary_types:string release_status:string release_country:string \
  label:string catalog_number:string barcode:string \
  disc_total:integer compilation:boolean

sleep 1
bundle exec rails g migration AddLibraryFieldsToSongs \
  disc_number:integer artist_credit:string \
  musicbrainz_recording_id:uuid:index musicbrainz_release_track_id:uuid:index

sleep 1
bundle exec rails g model SongArtistCredit \
  song:references artist:references position:integer --no-fixture
