class CreateSongs < ActiveRecord::Migration[8.0]
  def change
    create_table :songs do |t|
      t.string :title
      t.string :artist
      t.string :album
      t.string :genre
      t.integer :year
      t.integer :duration
      t.string :file_path
      t.integer :file_size
      t.integer :bitrate
      t.integer :sample_rate
      t.integer :channels

      t.timestamps
    end
  end
end
