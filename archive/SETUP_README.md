# Rails Application Setup

This document explains the setup process for the Rails application in the devcontainer.

## Setup Scripts

### `setup_gems.rb`
A Ruby script that ensures all required gems are present in the Gemfile. It checks for:
- `pundit` (authorization)
- `importmap-rails` (JavaScript import management)
- `turbo-rails` (Hotwire Turbo)

The script only adds gems if they're not already present, preventing duplicate entries.

### `setup_rails.sh`
A bash script that handles the complete Rails application setup:

1. **System Dependencies**: Installs `libpq-dev` for PostgreSQL support
2. **Gem Management**: Runs the gem setup script and installs all gems
3. **Rails Setup**: 
   - Installs Active Storage
   - Creates the database
   - Runs migrations
   - Installs Pundit authorization
   - Installs Importmap for JavaScript management
   - Pins Turbo Rails
   - Seeds the database

## Devcontainer Configuration

The `.devcontainer/devcontainer.json` file is configured to:
- Use the Rails devcontainer features
- Forward ports 3000 (Rails) and 5432 (PostgreSQL)
- Run the setup script automatically when the container is created
- Set up proper environment variables for PostgreSQL

## Manual Setup (if needed)

If you need to run the setup manually:

```bash
cd /workspaces/dockercrap/archive
./setup_rails.sh
```

## Troubleshooting

### Common Issues

1. **Database connection errors**: Ensure PostgreSQL is running and environment variables are set correctly
2. **Gem installation failures**: Check that all system dependencies are installed
3. **Migration errors**: Ensure the database exists and is accessible

### Reset Setup

To reset the setup and start fresh:

```bash
cd /workspaces/dockercrap/archive
bin/rails db:drop
bin/rails db:create
bin/rails db:migrate
bin/rails db:seed
```

## Development Workflow

After setup, you can:
- Start the Rails server: `bin/rails server`
- Run tests: `bin/rails test`
- Generate new components: `bin/rails generate`
- Access the application at `http://localhost:3000` 