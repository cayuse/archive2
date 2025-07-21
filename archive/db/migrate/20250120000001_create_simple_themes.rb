class CreateSimpleThemes < ActiveRecord::Migration[8.0]
  def change
    create_table :themes do |t|
      t.string :name, null: false, index: { unique: true }
      t.string :display_name, null: false
      t.text :description
      t.string :version, default: '1.0.0'
      t.boolean :is_active, default: true
      t.boolean :is_default, default: false
      
      # Color palette (21 colors)
      t.string :primary_bg, default: '#0f0f23'
      t.string :secondary_bg, default: '#1a1a2e'
      t.string :accent_color, default: '#4f46e5'
      t.string :accent_hover, default: '#6366f1'
      t.string :accent_active, default: '#3730a3'
      t.string :text_primary, default: '#f8fafc'
      t.string :text_secondary, default: '#cbd5e1'
      t.string :text_muted, default: '#64748b'
      t.string :text_inverse, default: '#ffffff'
      t.string :border_color, default: '#334155'
      t.string :shadow_color, default: 'rgba(0, 0, 0, 0.1)'
      t.string :overlay_color, default: 'rgba(0, 0, 0, 0.5)'
      t.string :success_color, default: '#10b981'
      t.string :warning_color, default: '#f59e0b'
      t.string :danger_color, default: '#ef4444'
      t.string :button_bg, default: '#374151'
      t.string :button_hover, default: '#4b5563'
      t.string :button_active, default: '#1f2937'
      t.string :highlight_color, default: '#3b82f6'
      t.string :link_color, default: '#60a5fa'
      t.string :link_hover, default: '#93c5fd'

      t.timestamps
    end

    create_table :theme_assets do |t|
      t.references :theme, null: false, foreign_key: { on_delete: :cascade }
      t.string :asset_type, null: false # 'icon', 'image', 'logo'
      t.string :filename, null: false
      t.string :display_name, null: false
      t.text :description
      t.binary :file_data, null: false
      t.string :content_type, null: false
      t.string :checksum, null: false
      t.integer :file_size, null: false
      
      t.timestamps
      
      t.index [:theme_id, :asset_type, :filename], unique: true
    end

    # Create default theme (without PowerSync for now)
    execute <<-SQL
      INSERT INTO themes (name, display_name, description, is_default, is_active, created_at, updated_at)
      VALUES ('default', 'Default Theme', 'The default dark theme for the archive', true, true, NOW(), NOW())
    SQL
  end
end 