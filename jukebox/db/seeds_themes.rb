# Create default theme for jukebox
default_theme = Theme.find_or_create_by(name: 'default') do |theme|
  theme.display_name = 'Default Theme'
  theme.description = 'Default theme for jukebox application'
  theme.primary_color = '#007bff'
  theme.secondary_color = '#6c757d'
  theme.accent_color = '#28a745'
  theme.background_color = '#ffffff'
  theme.surface_color = '#f8f9fa'
  theme.text_color = '#212529'
  theme.text_muted_color = '#6c757d'
  theme.border_color = '#dee2e6'
  theme.success_color = '#28a745'
  theme.warning_color = '#ffc107'
  theme.error_color = '#dc3545'
  theme.info_color = '#17a2b8'
  theme.link_color = '#007bff'
  theme.link_hover_color = '#0056b3'
  theme.button_primary_bg = '#007bff'
  theme.button_primary_text = '#ffffff'
  theme.button_secondary_bg = '#6c757d'
  theme.button_secondary_text = '#ffffff'
  theme.card_bg = '#ffffff'
  theme.card_border = '#dee2e6'
  theme.navbar_bg = '#343a40'
  theme.is_default = true
  theme.is_active = true
end

puts "Default theme created: #{default_theme.display_name}"

# Create a dark theme
dark_theme = Theme.find_or_create_by(name: 'dark') do |theme|
  theme.display_name = 'Dark Theme'
  theme.description = 'Dark theme for jukebox application'
  theme.primary_color = '#0d6efd'
  theme.secondary_color = '#6c757d'
  theme.accent_color = '#198754'
  theme.background_color = '#212529'
  theme.surface_color = '#343a40'
  theme.text_color = '#f8f9fa'
  theme.text_muted_color = '#adb5bd'
  theme.border_color = '#495057'
  theme.success_color = '#198754'
  theme.warning_color = '#ffc107'
  theme.error_color = '#dc3545'
  theme.info_color = '#0dcaf0'
  theme.link_color = '#0d6efd'
  theme.link_hover_color = '#0a58ca'
  theme.button_primary_bg = '#0d6efd'
  theme.button_primary_text = '#ffffff'
  theme.button_secondary_bg = '#6c757d'
  theme.button_secondary_text = '#ffffff'
  theme.card_bg = '#343a40'
  theme.card_border = '#495057'
  theme.navbar_bg = '#212529'
  theme.is_default = false
  theme.is_active = false
end

puts "Dark theme created: #{dark_theme.display_name}" 