# User Management System

## Overview

The Music Archive app includes a comprehensive user management system that allows administrators to create new users and automatically send them welcome emails with temporary passwords.

## Features

### 🔐 Authentication
- **Login System**: Users can log in with email and password
- **Session Management**: Secure session-based authentication
- **Role-Based Access**: Different permissions based on user roles

### 👥 User Roles
- **User**: Basic access to browse music and create playlists
- **Moderator**: Can manage content and moderate user-generated content
- **Admin**: Full access including user management

### 📧 Email Notifications
- **Welcome Emails**: Automatically sent when admins create new users
- **Temporary Passwords**: Secure random passwords generated for new users
- **Professional Templates**: HTML and text email templates included

## Admin User Management

### Creating New Users
1. **Login as Admin**: Use admin credentials to access the system
2. **Navigate to User Management**: Click "Manage Users" in the navigation
3. **Add New User**: Click "Add New User" button
4. **Fill Form**: Enter:
   - **Full Name**: User's display name
   - **Email**: User's email address
   - **Role**: Select appropriate role (defaults to 'user')
5. **Submit**: System will:
   - Generate a secure temporary password
   - Create the user account
   - Send welcome email with login credentials
   - Redirect to user list with success message

### Managing Existing Users
- **View All Users**: See complete list with roles and contact info
- **Edit Users**: Modify names, emails, and roles
- **Delete Users**: Remove users from the system (with confirmation)

## Email System

### Welcome Email Features
- **Professional Design**: Clean, responsive HTML template
- **Login Information**: Clear display of email and temporary password
- **Security Notes**: Instructions for password change on first login
- **Feature Overview**: Brief description of what users can do
- **Fallback Text**: Plain text version for email clients that don't support HTML

### Email Configuration
- **Development**: Uses `letter_opener` gem to preview emails in browser
- **Production**: Configured for SMTP delivery (update settings as needed)

## Security Features

### Password Security
- **Temporary Passwords**: 12-character alphanumeric passwords
- **Secure Generation**: Uses `SecureRandom.alphanumeric(12)`
- **Password Change**: Users should change password on first login
- **bcrypt Hashing**: All passwords securely hashed

### Access Control
- **Admin-Only Creation**: Only admins can create new users
- **Role-Based Authorization**: Pundit policies enforce permissions
- **Session Security**: Secure session management
- **Input Validation**: Email format and uniqueness validation

## Technical Implementation

### Key Components

#### Controllers
- `UsersController`: Admin user management (CRUD operations)
- `SessionsController`: Authentication (login/logout)

#### Models
- `User`: User model with roles, validations, and associations
- `UserMailer`: Email functionality for welcome messages

#### Views
- User management interface with modern UI
- Login form with error handling
- Email templates (HTML and text)

#### Routes
```ruby
# Authentication
get '/login', to: 'sessions#new'
post '/login', to: 'sessions#create'
delete '/logout', to: 'sessions#destroy'

# User management (admin only)
resources :users, except: [:show]
```

### Database Schema
```sql
users table:
- id (primary key)
- email (unique, indexed)
- name (not null)
- role (enum: user, moderator, admin)
- password_digest (bcrypt hash)
- timestamps
```

## Setup Instructions

### Initial Setup
1. **Run Migrations**: `bin/rails db:migrate`
2. **Seed Database**: `bin/rails db:seed` (creates admin user)
3. **Start Server**: `bin/rails server`

### Admin Access
- **Email**: `admin@musicarchive.com`
- **Password**: `admin123`

### Testing Email
- **Development**: Emails open in browser automatically
- **Production**: Configure SMTP settings in `config/environments/production.rb`

## Usage Examples

### Creating a New User (Admin)
```ruby
# In Rails console
user = User.new(
  name: "John Doe",
  email: "john@example.com",
  role: "user"
)
user.password = SecureRandom.alphanumeric(12)
user.save!

# Send welcome email
UserMailer.welcome_email(user, user.password).deliver_now
```

### Checking User Roles
```ruby
user.admin?     # => true/false
user.moderator? # => true/false (includes admins)
user.user?      # => true/false
```

## Troubleshooting

### Common Issues

1. **Email Not Sending**
   - Check development configuration in `config/environments/development.rb`
   - Verify `letter_opener` gem is installed
   - Check server logs for errors

2. **Authentication Issues**
   - Ensure user exists in database
   - Verify password is correct
   - Check session configuration

3. **Permission Errors**
   - Verify user has appropriate role
   - Check Pundit policies are properly configured
   - Ensure admin access for user management

### Development Tips
- Use `bin/rails console` to inspect users
- Check email previews in browser during development
- Use `bin/rails routes` to verify routing
- Monitor server logs for debugging

## Future Enhancements

### Potential Improvements
- **Password Reset**: Self-service password reset functionality
- **Email Verification**: Email confirmation for new accounts
- **User Profiles**: Extended user profile information
- **Activity Logging**: Track user actions and changes
- **Bulk Operations**: Import/export user data
- **Advanced Roles**: More granular permission system

### Security Enhancements
- **Two-Factor Authentication**: Additional security layer
- **Account Lockout**: Prevent brute force attacks
- **Session Timeout**: Automatic logout after inactivity
- **Audit Trail**: Log all administrative actions

## Support

For issues or questions about the user management system:
1. Check the server logs for error messages
2. Verify database migrations are up to date
3. Test email configuration in development
4. Review Pundit authorization policies 