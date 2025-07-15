class AddOriginalFilenameToSongs < ActiveRecord::Migration[8.0]
  def change
    add_column :songs, :original_filename, :string
  end
end
