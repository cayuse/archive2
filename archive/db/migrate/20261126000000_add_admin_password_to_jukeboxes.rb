# A second join code for the guest page. Guests who enter it get the admin
# controls (bump, remove, pause, skip); the guest code stays request-only.
class AddAdminPasswordToJukeboxes < ActiveRecord::Migration[8.0]
  def change
    add_column :jukeboxes, :admin_password, :string
  end
end
