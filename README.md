# Music Archive App

A Rails 8.0 music archive application with Docker and Dev Container support, featuring user management, role-based authentication, email notifications, and Bootstrap 5 for modern UI.

## Development Setup

### Option 1: Automated Setup Script (Recommended)
```bash
# Run the automated setup script from the project root
./setup.sh
```
This script will guide you through Docker or local development setup.

### Option 2: Using Dev Container (Recommended)

1. **Open in Dev Container**: 
   - Open this project in VS Code
   - When prompted, click "Reopen in Container" or use Command Palette: `Dev Containers: Reopen in Container`

2. **Automatic Setup**: 
   - The dev container will automatically install dependencies and set up the development environment
   - The Rails server will be available at `http://localhost:3000`

3. **Manual Setup** (if needed):
   ```bash
   cd archive
   ./bin/setup-dev
   bin/rails server
   ```

### Option 2: Local Development

1. **Prerequisites**:
   - Ruby 3.3.8
   - PostgreSQL 15
   - Node.js (for asset compilation)

2. **Required Files After Cloning**:
   
   **For Development:**
   ```bash
   # Create master key for Rails credentials (if using encrypted credentials)
   cd archive
   bin/rails credentials:edit
   # This will create config/master.key and config/credentials.yml.enc
   
   # Or create a simple master key file:
   echo "your-secret-master-key-here" > config/master.key
   ```
   
   **For Production:**
   ```bash
   # Set up your production master key
   export RAILS_MASTER_KEY="your-production-master-key"
   
   # Or create the master key file:
   echo "your-production-master-key" > config/master.key
   ```

3. **Setup**:
   ```bash
   cd archive
   ./bin/setup-dev
   bin/rails server
   ```



## Production Setup

### Using Docker

1. **Build the image**:
   ```bash
   docker build -t archive .
   ```

2. **Run the container**:
   ```bash
   docker run -d -p 80:80 \
     -e RAILS_MASTER_KEY=<your_master_key> \
     --name archive archive
   ```

### Using Kamal (Recommended for production)

1. **Configure deployment**:
   - Edit `archive/config/deploy.yml` with your server details
   - Set up your `RAILS_MASTER_KEY` environment variable

2. **Deploy**:
   ```bash
   cd archive
   kamal deploy
   ```

## Environment Variables

- `RAILS_MASTER_KEY`: Required for production (get from `archive/config/master.key`)
- `RAILS_ENV`: Set to `production` for production deployment
- `DATABASE_URL`: Optional, defaults to PostgreSQL in development

## Gitignored Files

The following files are not included in the repository and need to be created after cloning:

### Required Files
- `config/master.key`: Rails master key for encrypted credentials
- `storage/`: Directory for uploaded files (created automatically)
- `log/`: Directory for log files (created automatically)
- `tmp/`: Directory for temporary files (created automatically)

### Optional Files
- `.env`: Environment variables (if using dotenv gem)
- `.env.local`: Local environment variables
- `.env.development`: Development-specific environment variables

## Database

The app uses PostgreSQL:
- Development: `archive_development` database
- Test: `archive_test` database
- Production: Uses `DATABASE_URL` environment variable

### Database Setup
```bash
# Create databases
bin/rails db:create

# Run migrations
bin/rails db:migrate

# Seed database (if seeds exist)
bin/rails db:seed
```

## User Management System

The app includes a comprehensive user management system with:

### Authentication
- **Login System**: Email/password authentication
- **Role-Based Access**: User, Moderator, and Admin roles
- **Session Management**: Secure session-based authentication

### Admin Features
- **User Creation**: Admins can create new users with temporary passwords
- **Email Notifications**: Welcome emails sent automatically to new users
- **User Management**: View, edit, and delete user accounts with confirmation dialogs
- **Modern UI**: Bootstrap 5 for responsive, professional interface

### Initial Admin Access
- **Email**: `admin@musicarchive.com`
- **Password**: `admin123`

### Email Configuration
- **Development**: Uses `letter_opener` to preview emails in browser
- **Production**: Configure SMTP settings as needed

## Useful Commands

- `bin/rails server`: Start the Rails server
- `bin/rails console`: Open Rails console
- `bin/rails db:migrate`: Run database migrations
- `bin/rails db:seed`: Seed the database with admin user
- `bin/dev`: Start development server with file watching
- `./bin/setup-dev`: Complete development environment setup

## Project Structure

- `archive/`: Main Rails application
- `.devcontainer/`: Dev Container configuration
- `Dockerfile`: Production Docker configuration

## Troubleshooting

1. **Port conflicts**: Make sure port 3000 is available
2. **Database issues**: Run `bin/rails db:reset` to reset the database
3. **Permission issues**: In dev container, files are owned by `vscode` user
4. **Asset compilation**: Run `bin/rails assets:precompile` for production assets
5. **Missing master key**: Create `config/master.key` with a secure random key
6. **PostgreSQL connection**: Ensure PostgreSQL is running and accessible
7. **Gem installation issues**: Run `bundle install` to reinstall gems
8. **Email issues**: Check `config/environments/development.rb` for letter_opener configuration
9. **Authentication issues**: Verify user exists and password is correct
10. **Permission errors**: Ensure user has appropriate role for the action
11. **JavaScript issues**: Ensure Turbo is properly installed with `bin/importmap pin @hotwired/turbo-rails`
12. **Delete functionality**: Uses `button_to` for reliable DELETE requests with confirmation dialogs
13. **Bootstrap styling**: Uses Bootstrap 5 CDN for responsive design and modern components 