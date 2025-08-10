class CreateSystemSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :system_settings, if_not_exists: true do |t|
      t.string :key, null: false
      t.text :value, null: false
      t.text :description

      t.timestamps
    end
    add_index :system_settings, :key, unique: true, if_not_exists: true
  end
end


