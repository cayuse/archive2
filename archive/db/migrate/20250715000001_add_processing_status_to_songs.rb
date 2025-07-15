class AddProcessingStatusToSongs < ActiveRecord::Migration[8.0]
  def change
    add_column :songs, :processing_status, :string
    add_column :songs, :processing_error, :text
    
    # Add index for performance
    add_index :songs, :processing_status
    
    # Set default status for existing songs
    Song.update_all(processing_status: 'completed') if Song.exists?
  end
end 