class CreateJukeboxes < ActiveRecord::Migration[7.0]
  def change
    create_table :jukeboxes, id: :uuid do |t|
      t.string :name, null: false
      t.string :session_id, null: false
      t.string :password_hash
      t.uuid :owner_id, null: false
      t.boolean :private, default: false, null: false
      t.string :status, default: 'inactive', null: false
      t.timestamp :started_at
      t.timestamp :ended_at
      t.timestamp :scheduled_start
      t.timestamp :scheduled_end
      t.boolean :crossfade_enabled, default: true, null: false
      t.integer :crossfade_duration, default: 3000, null: false
      t.boolean :auto_play, default: true, null: false
      t.text :description
      t.string :location

      t.timestamps
    end

    add_index :jukeboxes, :owner_id
    add_index :jukeboxes, :session_id, unique: true
    add_index :jukeboxes, :status
    add_index :jukeboxes, :private
    add_index :jukeboxes, :created_at
    add_index :jukeboxes, [:private, :status], where: "private = false"
  end
end
