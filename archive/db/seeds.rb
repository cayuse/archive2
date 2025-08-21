# Create initial admin user only
# WARNING: Change this password immediately after first login!
admin = User.find_or_create_by(email: 'admin@musicarchive.com') do |user|
  user.name = 'System Administrator'
  user.password = 'admin123'
  user.password_confirmation = 'admin123'
  user.role = 'admin'
end

puts "Admin user created: #{admin.email}"
puts "WARNING: Default password is 'admin123' - CHANGE THIS IMMEDIATELY!"

# Create the complete default theme
default_theme = Theme.find_or_create_by(name: 'default') do |theme|
  theme.display_name = 'Default Theme'
  theme.description = 'The default dark theme for the archive'
  theme.version = '1.0.0'
  theme.is_active = true
  theme.is_default = true
  
  # Complete color palette (21 colors)
  theme.primary_bg = '#0f0f23'
  theme.secondary_bg = '#1a1a2e'
  theme.accent_color = '#4f46e5'
  theme.accent_hover = '#6366f1'
  theme.accent_active = '#3730a3'
  theme.text_primary = '#f8fafc'
  theme.text_secondary = '#cbd5e1'
  theme.text_muted = '#64748b'
  theme.text_inverse = '#ffffff'
  theme.border_color = '#334155'
  theme.shadow_color = 'rgba(0, 0, 0, 0.1)'
  theme.overlay_color = 'rgba(0, 0, 0, 0.5)'
  theme.success_color = '#10b981'
  theme.warning_color = '#f59e0b'
  theme.danger_color = '#ef4444'
  theme.button_bg = '#374151'
  theme.button_hover = '#4b5563'
  theme.button_active = '#1f2937'
  theme.highlight_color = '#3b82f6'
  theme.link_color = '#60a5fa'
  theme.link_hover = '#93c5fd'
  
  # Additional theme properties
  theme.heading_color = '#f8fafc'  # Same as text_primary for consistency
  theme.card_header_text = 'Music Archive'  # Same as site name for consistency
  theme.css_variables = {}
  theme.custom_css = nil
end

puts "Default theme created/updated: #{default_theme.name}"

# Initialize system settings
SystemSetting.set('current_theme', 'default', 'Currently active theme')
SystemSetting.set('site_name', 'Music Archive', 'Site name displayed in navigation')
SystemSetting.set('site_description', 'A comprehensive music archive system', 'Site description for SEO')

puts "System settings initialized"
puts "Seeding completed!"
puts ""
puts "SECURITY REMINDER:"
puts "- Change the admin password immediately after first login"
puts "- Create additional users through the web interface"
puts "- Never commit passwords to version control"
