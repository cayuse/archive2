class CreateGenreAffinities < ActiveRecord::Migration[8.0]
  def change
    create_table :genre_affinities, id: :uuid do |t|
      t.references :genre, null: false, foreign_key: { on_delete: :cascade }, type: :uuid, index: false
      t.references :related_genre, null: false, foreign_key: { to_table: :genres, on_delete: :cascade }, type: :uuid
      t.float :score, null: false

      t.timestamps
    end

    add_index :genre_affinities, [ :genre_id, :related_genre_id ], unique: true
  end
end
