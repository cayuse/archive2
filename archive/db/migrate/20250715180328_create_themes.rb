class CreateThemes < ActiveRecord::Migration[8.0]
  def change
    create_table :themes do |t|
      t.string :name
      t.string :display_name
      t.text :description
      t.boolean :active
      t.text :config

      t.timestamps
    end
  end
end
