class CleanupOldThemeTables < ActiveRecord::Migration[8.0]
  def up
    # Drop tables in dependency order
    drop_table :theme_assets if table_exists?(:theme_assets)
    drop_table :theme_settings if table_exists?(:theme_settings)
    
    # Remove theme references from system_settings
    if table_exists?(:system_settings) && column_exists?(:system_settings, :theme_id)
      remove_reference :system_settings, :theme, foreign_key: true
    end
    
    # Drop the themes table with CASCADE to handle dependencies
    execute "DROP TABLE IF EXISTS themes CASCADE" if table_exists?(:themes)
  end

  def down
    # This migration is destructive, so we don't provide a rollback
    raise ActiveRecord::IrreversibleMigration
  end
end 