class ChangePasswordHashToGuestPassword < ActiveRecord::Migration[7.0]
  def up
    # Remove the old password_hash column
    remove_column :jukeboxes, :password_hash, :string
    
    # Add the new guest_password column as plain text
    add_column :jukeboxes, :guest_password, :string
    
    # Add an index for performance
    add_index :jukeboxes, :guest_password
  end

  def down
    # Remove the new guest_password column
    remove_column :jukeboxes, :guest_password, :string
    
    # Add back the old password_hash column
    add_column :jukeboxes, :password_hash, :string
  end
end
