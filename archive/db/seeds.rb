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
