class AddMusicbrainzFieldsToArtists < ActiveRecord::Migration[8.0]
  def change
    add_column :artists, :musicbrainz_id, :uuid
    add_index :artists, :musicbrainz_id, unique: true
    add_column :artists, :sort_name, :string
    add_column :artists, :disambiguation, :string
    add_column :artists, :artist_type, :string

    # Different artists can share a name ("Free", "Harvest"); identity is the MusicBrainz id when present.
    remove_index :artists, :name, unique: true, name: "index_artists_on_name"
    add_index :artists, :name
  end
end
