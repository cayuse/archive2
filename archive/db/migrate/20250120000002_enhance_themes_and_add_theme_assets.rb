class EnhanceThemesAndAddThemeAssets < ActiveRecord::Migration[8.0]
  def change
    # Enhance existing themes table - only add missing columns
    change_table :themes do |t|
      # Add new columns for enhanced theme system (skip ones that already exist)
      t.jsonb :css_variables, default: {}
      t.text :custom_css
    end
    
    # Create theme_settings table (theme_assets already exists from previous migration)
    create_table :theme_settings, id: :uuid, default: -> { 'gen_random_uuid()' } do |t|
      t.string :key, null: false, index: { unique: true }
      t.text :value, null: false
      t.string :description
      t.timestamps
    end
    
    # Add theme reference to system settings if table/column state allows
    if table_exists?(:system_settings) && !column_exists?(:system_settings, :theme_id)
      add_reference :system_settings, :theme, foreign_key: true, null: true, type: :uuid
    end
  end
end 