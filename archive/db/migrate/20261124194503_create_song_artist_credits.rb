class CreateSongArtistCredits < ActiveRecord::Migration[8.0]
  def change
    create_table :song_artist_credits, id: :uuid do |t|
      t.references :song, null: false, foreign_key: { on_delete: :cascade }, type: :uuid, index: false
      t.references :artist, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :song_artist_credits, [ :song_id, :artist_id ], unique: true
  end
end
