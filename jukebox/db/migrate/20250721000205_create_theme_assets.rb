class CreateThemeAssets < ActiveRecord::Migration[8.0]
  def change
    create_table :theme_assets do |t|
      t.references :theme, null: false, foreign_key: true
      t.string :asset_type, null: false
      t.string :filename, null: false
      t.string :display_name, null: false
      t.text :description
      t.string :url
      t.integer :size
      t.string :mime_type

      t.timestamps
    end

    add_index :theme_assets, [:theme_id, :asset_type, :filename], unique: true
  end
end
