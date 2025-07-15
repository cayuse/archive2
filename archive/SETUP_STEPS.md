# Rails Development Environment Setup

This is a simple, step-by-step guide to set up your Rails development environment.

## Prerequisites
- Devcontainer is running and stable
- You're in the `/workspaces/dockercrap/archive` directory

## Step 1: Install System Dependencies
```bash
sudo apt update
sudo apt install -y libpq-dev
```

## Step 2: Install Ruby Gems
```bash
bundle install
```

## Step 3: Setup Database
```bash
bin/rails db:create
bin/rails db:migrate
```

## Step 4: Install Rails Components (if needed)
```bash
# Active Storage (for file uploads)
bin/rails active_storage:install

# Pundit (authorization) - only if not already installed
bin/rails generate pundit:install

# Importmap (JavaScript management) - only if not already installed
bin/rails importmap:install
bin/importmap pin @hotwired/turbo-rails
```

## Step 5: Seed Database (if needed)
```bash
bin/rails db:seed
```

## Step 6: Start Development Server
```bash
bin/rails server
```

## Troubleshooting

### If bundle install fails:
```bash
rm -rf ~/.cache/gem/specs
rm -rf vendor/bundle
bundle install --retry=3
```

### If database connection fails:
- Check that PostgreSQL container is running
- Verify environment variables are set correctly
- Try: `bin/rails db:drop && bin/rails db:create`

### If you need to reset everything:
```bash
bin/rails db:drop
bin/rails db:create
bin/rails db:migrate
bin/rails db:seed
```

## Quick Status Check
```bash
# Check if gems are installed
bundle list

# Check if database exists
bin/rails db:version

# Check if server starts
bin/rails server -p 3000 -d
curl http://localhost:3000
bin/rails server -p 3000 -d --pid tmp/pids/server.pid
```

## Development Commands
- Start server: `bin/rails server`
- Run tests: `bin/rails test`
- Generate new model: `bin/rails generate model`
- Access Rails console: `bin/rails console` 