class AddLibraryFieldsToSongs < ActiveRecord::Migration[8.0]
  def change
    add_column :songs, :disc_number, :integer
    add_column :songs, :artist_credit, :string
    add_column :songs, :musicbrainz_recording_id, :uuid
    add_index :songs, :musicbrainz_recording_id
    add_column :songs, :musicbrainz_release_track_id, :uuid
    add_index :songs, :musicbrainz_release_track_id
  end
end
