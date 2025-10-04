class CreateAjbQueueItems < ActiveRecord::Migration[7.0]
  def change
    create_table :ajb_queue_items, id: :uuid do |t|
      t.uuid :jukebox_id, null: false
      t.uuid :song_id, null: false
      t.integer :position, null: false
      t.string :source, null: false, default: 'random'

      t.timestamps
    end

    # Indexes for performance
    add_index :ajb_queue_items, :jukebox_id
    add_index :ajb_queue_items, :song_id
    add_index :ajb_queue_items, [:jukebox_id, :position]
    add_index :ajb_queue_items, [:jukebox_id, :source]
    
    # Foreign key constraints
    add_foreign_key :ajb_queue_items, :jukeboxes, column: :jukebox_id, on_delete: :cascade
    add_foreign_key :ajb_queue_items, :songs, column: :song_id, on_delete: :cascade
    
    # Check constraints
    add_check_constraint :ajb_queue_items, "position > 0", name: "check_positive_position"
    add_check_constraint :ajb_queue_items, "source IN ('random', 'requested')", name: "check_valid_source"
  end
end
