class AddQueueFieldsToJukeboxes < ActiveRecord::Migration[7.0]
  def change
    add_column :jukeboxes, :min_queue_length, :integer, default: 5, null: false
    add_column :jukeboxes, :queue_refill_level, :integer, default: 10, null: false
    
    # Add check constraints to ensure positive values
    add_check_constraint :jukeboxes, "min_queue_length > 0", name: "check_positive_min_queue_length"
    add_check_constraint :jukeboxes, "queue_refill_level > 0", name: "check_positive_queue_refill_level"
  end
end
