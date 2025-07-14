# Quick Start Guide - User Management System

## 🚀 Getting Started

### 1. Start the Application
```bash
# Using Docker Compose (recommended)
docker-compose up

# Or using Rails directly
cd archive
bin/rails server
```

### 2. Access the Application
- **URL**: http://localhost:3000
- **Admin Login**: 
  - Email: `admin@musicarchive.com`
  - Password: `admin123`

### 3. Create Your First User
1. **Login as Admin**: Use the credentials above
2. **Navigate to User Management**: Click "Manage Users" in the navigation
3. **Add New User**: Click "Add New User" button
4. **Fill the Form**:
   - **Name**: Enter the user's full name
   - **Email**: Enter a valid email address
   - **Role**: Select appropriate role (defaults to 'user')
5. **Submit**: The system will:
   - Generate a secure temporary password
   - Create the user account
   - Send a welcome email (opens in browser)
   - Show success message

## 📧 Email System

### Development Environment
- **Email Preview**: Welcome emails automatically open in your browser
- **No SMTP Required**: Uses `letter_opener` gem for development
- **Template**: Professional HTML and text versions included

### Production Environment
- **SMTP Configuration**: Update `config/environments/production.rb`
- **Email Delivery**: Configure your email service provider

## 🔐 User Roles

### Admin
- **Full Access**: Can manage all users and content
- **User Creation**: Can create new users with temporary passwords
- **System Management**: Complete administrative control

### Moderator
- **Content Management**: Can moderate user-generated content
- **Limited Admin**: Some administrative functions
- **User Management**: Cannot create new users

### User
- **Basic Access**: Browse music and create playlists
- **Standard Features**: Normal user functionality
- **No Admin**: Cannot access administrative features

## 🛠️ Development Commands

```bash
# Start the server
bin/rails server

# Open Rails console
bin/rails console

# Reset database (includes seeding)
bin/rails db:reset

# View all routes
bin/rails routes

# Check user management routes
bin/rails routes | grep user
```

## 📋 Testing the System

### 1. Test User Creation
```ruby
# In Rails console
user = User.new(name: "Test User", email: "test@example.com", role: "user")
user.password = "temp123"
user.save!

# Send welcome email
UserMailer.welcome_email(user, "temp123").deliver_now
```

### 2. Test Authentication
```ruby
# In Rails console
user = User.find_by(email: "admin@musicarchive.com")
user.authenticate("admin123") # Should return user object
```

### 3. Test Role Methods
```ruby
# In Rails console
user = User.find_by(email: "admin@musicarchive.com")
user.admin?     # => true
user.moderator? # => true (includes admins)
user.user?      # => false
```

## 🔧 Configuration Files

### Email Configuration
- **Development**: `config/environments/development.rb`
- **Production**: `config/environments/production.rb`

### User Model
- **Location**: `app/models/user.rb`
- **Validations**: Email format, name length, role inclusion
- **Methods**: Role checking, display name, etc.

### Controllers
- **User Management**: `app/controllers/users_controller.rb`
- **Authentication**: `app/controllers/sessions_controller.rb`

### Views
- **User Management**: `app/views/users/`
- **Email Templates**: `app/views/user_mailer/`
- **Authentication**: `app/views/sessions/`

## 🚨 Troubleshooting

### Common Issues

1. **"User not found" error**
   - Run `bin/rails db:seed` to create admin user
   - Check database connection

2. **Email not opening in browser**
   - Verify `letter_opener` gem is installed
   - Check `config/environments/development.rb` configuration

3. **Permission denied errors**
   - Ensure user has appropriate role
   - Check Pundit policies are loaded

4. **Database errors**
   - Run `bin/rails db:migrate` to ensure all migrations are applied
   - Run `bin/rails db:seed` to create initial data

### Debug Commands
```bash
# Check database status
bin/rails db:migrate:status

# View application logs
tail -f log/development.log

# Test email delivery
bin/rails console
UserMailer.welcome_email(User.first, "test123").deliver_now
```

## 📚 Next Steps

1. **Customize Email Templates**: Edit `app/views/user_mailer/welcome_email.html.erb`
2. **Add More Roles**: Extend the role system in `app/models/user.rb`
3. **Enhance Security**: Add password reset functionality
4. **Improve UI**: Customize the user management interface
5. **Add Features**: Implement user profiles, activity logging, etc.

## 📞 Support

For issues or questions:
1. Check the server logs for error messages
2. Verify all migrations are applied
3. Test email configuration
4. Review the comprehensive documentation in `USER_MANAGEMENT.md` 