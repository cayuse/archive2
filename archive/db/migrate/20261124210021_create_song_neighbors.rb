class CreateSongNeighbors < ActiveRecord::Migration[8.0]
  def change
    create_table :song_neighbors, id: :uuid do |t|
      t.references :song, null: false, foreign_key: { on_delete: :cascade }, type: :uuid, index: false
      t.references :neighbor, null: false, foreign_key: { to_table: :songs, on_delete: :cascade }, type: :uuid
      t.integer :rank, null: false
      t.float :score, null: false

      t.timestamps
    end

    add_index :song_neighbors, [ :song_id, :rank ], unique: true
  end
end
