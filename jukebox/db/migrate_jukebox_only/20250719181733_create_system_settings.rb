class CreateSystemSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :system_settings, if_not_exists: true do |t|
      t.string :key, null: false
      t.text :value, null: false
      t.text :description

      t.timestamps
    end
    
    # Only add unique index if it doesn't already exist
    # Check for existing index first to avoid conflicts with existing data
    unless index_exists?(:system_settings, :key, unique: true)
      # Remove any duplicate keys before adding unique constraint
      execute <<-SQL
        DELETE FROM system_settings a USING (
          SELECT MIN(ctid) as ctid, key
          FROM system_settings 
          GROUP BY key HAVING COUNT(*) > 1
        ) b
        WHERE a.key = b.key AND a.ctid <> b.ctid;
      SQL
      
      add_index :system_settings, :key, unique: true
    end
  end
end


