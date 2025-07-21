class EnsureDefaultThemeExists < ActiveRecord::Migration[8.0]
  def up
    # Create default theme if it doesn't exist
    unless Theme.exists?(name: 'default')
      Theme.create!(
        name: 'default',
        display_name: 'Default Theme',
        description: 'The default dark theme for the Music Archive',
        version: '1.0.0',
        is_default: true,
        is_active: true,
        # 21 Core Color Variables
        primary_bg: '#0f0f23',
        secondary_bg: '#1a1a2e',
        accent_color: '#4f46e5',
        accent_hover: '#6366f1',
        accent_active: '#3730a3',
        text_primary: '#f8fafc',
        text_secondary: '#cbd5e1',
        text_muted: '#64748b',
        text_inverse: '#ffffff',
        border_color: '#334155',
        shadow_color: 'rgba(0, 0, 0, 0.1)',
        overlay_color: 'rgba(0, 0, 0, 0.5)',
        success_color: '#10b981',
        warning_color: '#f59e0b',
        danger_color: '#ef4444',
        button_bg: '#374151',
        button_hover: '#4b5563',
        button_active: '#1f2937',
        highlight_color: '#3b82f6',
        link_color: '#60a5fa',
        link_hover: '#93c5fd'
      )
    end
    
    # Update system setting to use database theme
    SystemSetting.set('current_theme', 'default', 'Currently active theme')
  end

  def down
    # Remove the default theme
    Theme.where(name: 'default').destroy_all
  end
end 