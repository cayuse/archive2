# The drop box: a batch is one drop (files, folders, archives); an item is what became of each file in it.
class CreateIntake < ActiveRecord::Migration[8.1]
  def change
    create_table :intake_batches, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.string :name
      t.string :status, null: false, default: "uploading"
      t.datetime :started_at
      t.datetime :finished_at
      t.text :error
      t.timestamps
    end
    add_index :intake_batches, [ :status, :created_at ]

    create_table :intake_items, id: :uuid do |t|
      t.references :intake_batch, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :relative_path, null: false
      t.bigint :byte_size
      t.string :checksum
      t.string :status, null: false, default: "received"
      t.string :identified
      t.float :match_score
      t.references :song, type: :uuid, foreign_key: { on_delete: :nullify }
      t.text :message
      t.timestamps
    end
    add_index :intake_items, [ :intake_batch_id, :relative_path ], unique: true
    add_index :intake_items, :checksum
  end
end
