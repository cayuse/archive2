class CreateAlbums < ActiveRecord::Migration[8.0]
  def change
    create_table :albums do |t|
      t.string :title, null: false
      t.references :artist, null: false, foreign_key: true
      t.date :release_date
      t.text :description
      t.string :cover_image_url
      t.integer :total_tracks
      t.integer :duration

      t.timestamps
    end
    
    # Add indexes for performance and data integrity
    add_index :albums, :title
    add_index :albums, :release_date
    add_index :albums, :total_tracks
    
    # Add check constraints
    add_check_constraint :albums, "total_tracks IS NULL OR total_tracks > 0", name: "check_positive_total_tracks"
    add_check_constraint :albums, "duration IS NULL OR duration > 0", name: "check_positive_duration"
    add_check_constraint :albums, "release_date IS NULL OR release_date >= '1900-01-01'", name: "check_reasonable_release_date"
  end
end
