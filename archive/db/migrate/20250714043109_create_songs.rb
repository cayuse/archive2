class CreateSongs < ActiveRecord::Migration[8.0]
  def change
    create_table :songs, id: :uuid, default: -> { 'gen_random_uuid()' } do |t|
      t.string :title, null: false
      t.references :album, null: false, foreign_key: true, type: :uuid
      t.integer :track_number
      t.integer :duration
      t.string :file_format
      t.bigint :file_size

      t.timestamps
    end
    
    # Add indexes for performance and data integrity
    add_index :songs, :title
    add_index :songs, :track_number
    add_index :songs, :file_format
    add_index :songs, [:album_id, :track_number], unique: true
    
    # Add check constraints
    add_check_constraint :songs, "track_number IS NULL OR track_number > 0", name: "check_positive_track_number"
    add_check_constraint :songs, "duration IS NULL OR duration > 0", name: "check_positive_duration"
    add_check_constraint :songs, "file_size IS NULL OR file_size > 0", name: "check_positive_file_size"
  end
end
