class CreateSongRatings < ActiveRecord::Migration[8.0]
  def change
    create_table :song_ratings, id: :uuid do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, type: :uuid, index: false
      t.references :song, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      # 1 = thumbs up, -1 = thumbs down
      t.integer :value, null: false

      t.timestamps
    end

    add_index :song_ratings, [ :user_id, :song_id ], unique: true
  end
end
