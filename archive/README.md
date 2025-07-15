# Music Archive App

A modern Rails 8 music archive application with PostgreSQL, Active Storage, and role-based authorization using Pundit.

## 🎵 Features

- **User Authentication**: Secure password authentication with bcrypt
- **Role-Based Authorization**: User, Moderator, and Admin roles with Pundit
- **Music Management**: Artists, Albums, Songs, and Genres
- **Active Storage**: Audio file uploads and management
- **Playlists**: User-created playlists with public/private options
- **PostgreSQL**: Robust database with proper constraints and indexes
- **Docker Support**: Full containerization with devcontainer

## 🚀 Quick Start

### Option 1: Dev Container (Recommended)
1. Open the project in VS Code with Dev Containers extension
2. The container will automatically set up everything
3. Access the app at http://localhost:3000

### Option 2: Manual Setup
```bash
# Clone the repository
git clone <repository-url>
cd archive

# Run the setup script
./bin/setup-dev

# Start the server
bin/rails server
```

### Option 3: Docker Compose
```bash
# Start all services
docker-compose up

# Access the app at http://localhost:3000
```

## 📋 Prerequisites

- Ruby 3.3.8
- PostgreSQL 15
- Docker (for containerized setup)

## 🔧 Dependencies

### Core Gems
- **Rails 8.0.2**: Modern Rails framework
- **PostgreSQL**: Database adapter
- **bcrypt**: Password hashing
- **Pundit**: Authorization system
- **Active Storage**: File uploads
- **Puma**: Web server

### Development Gems
- **Debug**: Ruby debugging
- **Brakeman**: Security analysis
- **RuboCop**: Code linting

## 🗄️ Database

The app uses PostgreSQL with the following models:
- **Users**: Authentication and role management
- **Artists**: Musicians and bands
- **Albums**: Music albums
- **Songs**: Individual tracks with audio files
- **Genres**: Music categories
- **Playlists**: User-created collections

## 🔐 Authorization

### Roles
- **User (0)**: Basic access, create playlists
- **Moderator (1)**: Content management
- **Admin (2)**: Full system access

### Usage
```ruby
# In controllers
authorize @artist
@artists = policy_scope(Artist)

# In views
<% if policy(@artist).update? %>
  <%= link_to 'Edit', edit_artist_path(@artist) %>
<% end %>
```

## 📁 Project Structure

```
archive/
├── app/
│   ├── models/          # ActiveRecord models
│   ├── controllers/     # Controllers with authorization
│   ├── policies/        # Pundit authorization policies
│   └── views/           # ERB templates
├── db/
│   ├── migrate/         # Database migrations
│   └── schema.rb        # Database schema
├── bin/
│   └── setup-dev        # Development setup script
├── .devcontainer/       # Dev container configuration
├── docker-compose.yml   # Multi-container orchestration
└── Dockerfile          # Production container
```

## 🧪 Testing

```bash
# Run all tests
bin/rails test

# Run specific test files
bin/rails test test/models/user_test.rb

# Run policy tests
bin/rails test test/policies/
```

## 📚 Documentation

- `USAGENOTES.txt`: Comprehensive usage guide
- `PUNDIT_AUTHORIZATION.md`: Authorization system documentation
- `MIGRATION_PLANS.md`: Database migration details

## 🔄 Development

### Common Commands
```bash
# Rails console
bin/rails console

# Database operations
bin/rails db:migrate
bin/rails db:reset
bin/rails db:seed

# Asset compilation
bin/rails assets:precompile

# Routes
bin/rails routes
```

### Adding New Features
1. Create migrations: `bin/rails generate migration`
2. Create models: `bin/rails generate model`
3. Create policies: `bin/rails generate pundit:policy`
4. Create controllers: `bin/rails generate controller`

## 🐳 Docker

### Development
```bash
# Start development environment
docker-compose up

# Rebuild containers
docker-compose build --no-cache
docker-compose up
```

### Production
```bash
# Build production image
docker build -t archive .

# Run production container
docker run -d -p 80:80 -e RAILS_MASTER_KEY=<key> archive
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License.

---

**Last Updated**: July 2025
**Rails Version**: 8.0.2
**Ruby Version**: 3.3.8

## Email Configuration
- **Development**: Uses `letter_opener` to preview emails in browser
- **Production**: Configure SMTP settings as needed

## Environment Variables for Email Delivery (SendGrid)

To enable email delivery via SendGrid in production, set the following environment variables:

| Variable            | Purpose                                 | Example Value                |
|---------------------|-----------------------------------------|------------------------------|
| SENDGRID_API_KEY    | SendGrid API key for email delivery     | SG.xxxxxxxx                  |
| APP_HOST            | Hostname for links in emails            | musicarchive.com             |
| RAILS_MASTER_KEY    | Rails credentials decryption key        | (from config/master.key)     |
| DATABASE_URL        | Database connection string (optional)   | postgres://...               |

### How to Set Environment Variables

**Docker Compose:**
```yaml
environment:
  SENDGRID_API_KEY: your-real-sendgrid-api-key
  APP_HOST: yourdomain.com
  RAILS_MASTER_KEY: your-rails-master-key
```

**Linux/Unix Shell:**
```bash
export SENDGRID_API_KEY=your-real-sendgrid-api-key
export APP_HOST=yourdomain.com
export RAILS_MASTER_KEY=your-rails-master-key
```

**Cloud Providers:**
Use their environment variable or secret management UI.

> **Never commit these secrets to version control.** Use your deployment’s secret management or environment variable system.
