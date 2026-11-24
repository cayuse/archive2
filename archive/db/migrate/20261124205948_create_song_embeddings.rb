class CreateSongEmbeddings < ActiveRecord::Migration[8.0]
  def change
    create_table :song_embeddings, id: :uuid do |t|
      t.references :song, null: false, foreign_key: { on_delete: :cascade }, type: :uuid, index: { unique: true }
      t.string :analysis_model
      t.integer :dimensions
      # L2-normalised vector as 4-byte floats; plain array so no database extension is needed
      t.float :embedding, array: true, limit: 24, null: false, default: []

      t.timestamps
    end
  end
end
