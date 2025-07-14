# Create initial admin user
admin = User.find_or_create_by(email: 'admin@musicarchive.com') do |user|
  user.name = 'System Administrator'
  user.password = 'admin123'
  user.password_confirmation = 'admin123'
  user.role = 'admin'
end

puts "Admin user created: #{admin.email} (password: admin123)"

# Create some sample users for testing
if User.count < 5
  users_data = [
    { name: 'John Doe', email: 'john@example.com', role: 'user' },
    { name: 'Jane Smith', email: 'jane@example.com', role: 'moderator' },
    { name: 'Bob Wilson', email: 'bob@example.com', role: 'user' }
  ]
  
  users_data.each do |user_data|
    user = User.find_or_create_by(email: user_data[:email]) do |u|
      u.name = user_data[:name]
      u.password = 'password123'
      u.password_confirmation = 'password123'
      u.role = user_data[:role]
    end
    puts "User created: #{user.email} (#{user.role})"
  end
end

puts "Seeding completed!"
