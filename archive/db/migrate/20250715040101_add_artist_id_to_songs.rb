class AddArtistIdToSongs < ActiveRecord::Migration[8.0]
  def change
    add_reference :songs, :artist, null: true, foreign_key: true
    
    # Populate artist_id from existing album relationships
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE songs 
          SET artist_id = albums.artist_id 
          FROM albums 
          WHERE songs.album_id = albums.id 
          AND songs.artist_id IS NULL
        SQL
      end
    end
  end
end
