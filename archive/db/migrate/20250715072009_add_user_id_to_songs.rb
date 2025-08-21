class AddUserIdToSongs < ActiveRecord::Migration[8.0]
  def change
    add_reference :songs, :user, null: true, foreign_key: true, type: :uuid
  end
end
