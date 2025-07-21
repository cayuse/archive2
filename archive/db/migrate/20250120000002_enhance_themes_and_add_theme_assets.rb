class EnhanceThemesAndAddThemeAssets < ActiveRecord::Migration[8.0]
  def change
    # Enhance existing themes table
    change_table :themes do |t|
      # Add missing columns and constraints
      t.change :name, :string, null: false
      t.change :display_name, :string, null: false
      
      # Add new columns for enhanced theme system
      t.boolean :is_default, default: false
      t.boolean :is_active, default: true
      t.jsonb :css_variables, default: {}
      t.text :custom_css
      t.string :version, default: '1.0.0'
      
      # Rename existing columns for consistency
      t.rename :active, :is_active_old
      t.rename :config, :config_old
    end
    
    # Add index separately
    add_index :themes, :name, unique: true
    
    # Create theme_assets table
    create_table :theme_assets do |t|
      t.references :theme, null: false, foreign_key: true
      t.string :asset_type, null: false # 'icon', 'image', 'logo', 'css'
      t.string :filename, null: false
      t.string :content_type, null: false
      t.binary :file_data, null: false
      t.integer :file_size, null: false
      t.string :checksum, null: false
      t.jsonb :metadata, default: {}
      t.timestamps
      
      t.index [:theme_id, :asset_type, :filename], unique: true, name: 'index_theme_assets_unique'
    end
    
    # Create theme_settings table
    create_table :theme_settings do |t|
      t.string :key, null: false, index: { unique: true }
      t.text :value, null: false
      t.string :description
      t.timestamps
    end
    
    # Add theme reference to system settings if it doesn't exist
    unless column_exists?(:system_settings, :theme_id)
      add_reference :system_settings, :theme, foreign_key: true, null: true
    end
  end
end 