class CreateSongFileTags < ActiveRecord::Migration[8.0]
  def change
    # What is embedded in each song's audio file, read as-is by the tag scanner.
    # One row per song. This is evidence for the library cleanup, not the cleaned-up result.
    create_table :song_file_tags, id: :uuid do |t|
      t.references :song, null: false, foreign_key: { on_delete: :cascade }, type: :uuid, index: { unique: true }
      t.string :blob_key
      t.string :blob_checksum
      t.string :container
      t.string :codec
      t.string :tag_format
      t.integer :bitrate
      t.string :bitrate_mode
      t.integer :sample_rate
      t.integer :channels
      t.integer :bits_per_sample
      t.float :duration_seconds
      t.string :title
      t.string :artist
      t.string :album
      t.string :album_artist
      t.string :composer
      t.string :genre
      t.integer :track_number
      t.integer :track_total
      t.integer :disc_number
      t.integer :disc_total
      t.string :date_raw
      t.string :original_date_raw
      t.integer :year
      t.boolean :compilation
      t.string :artist_sort
      t.string :album_artist_sort
      t.string :album_sort
      t.string :label
      t.string :catalog_number
      t.string :barcode
      t.string :isrc
      t.string :asin
      t.string :media
      t.string :release_type
      t.string :release_status
      t.string :release_country
      t.string :language
      t.string :script
      t.float :bpm
      t.uuid :musicbrainz_recording_id
      t.uuid :musicbrainz_release_id
      t.uuid :musicbrainz_release_group_id
      t.uuid :musicbrainz_release_track_id
      t.uuid :musicbrainz_work_id
      t.uuid :musicbrainz_artist_ids, array: true, null: false, default: []
      t.uuid :musicbrainz_album_artist_ids, array: true, null: false, default: []
      t.uuid :acoustid_id
      t.text :acoustid_fingerprint
      t.boolean :has_cover_art, null: false, default: false
      t.boolean :has_lyrics, null: false, default: false
      t.jsonb :raw_tags, null: false, default: {}
      t.text :scan_error
      t.datetime :scanned_at

      t.timestamps
    end

    add_index :song_file_tags, :musicbrainz_recording_id
    add_index :song_file_tags, :musicbrainz_release_id
    add_index :song_file_tags, :musicbrainz_release_group_id
    add_index :song_file_tags, :musicbrainz_artist_ids, using: :gin
    add_index :song_file_tags, :musicbrainz_album_artist_ids, using: :gin
    add_index :song_file_tags, :acoustid_id
    add_index :song_file_tags, :blob_key
  end
end
