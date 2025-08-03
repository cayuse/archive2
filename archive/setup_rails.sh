#!/bin/bash

# Rails setup script for devcontainer
# This script handles all the Rails initialization steps with improved error handling

set -e

echo "Starting Rails setup..."

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to handle errors gracefully
handle_error() {
    log "ERROR: $1"
    log "Setup failed. Check the logs above for details."
    exit 1
}

# Install PostgreSQL development libraries
log "Installing PostgreSQL development libraries..."
sudo apt update || handle_error "Failed to update package list"
sudo apt install -y libpq-dev postgresql-client || handle_error "Failed to install PostgreSQL dependencies"

# Verify Ruby is available and check version
log "Verifying Ruby installation..."
if ! command -v ruby &> /dev/null; then
    handle_error "Ruby not found. This should be available in the Rails dev container."
fi

RUBY_VERSION=$(ruby --version | cut -d' ' -f2)
log "Ruby version: $RUBY_VERSION"

# Change to the Rails application directory
cd /workspaces/dockercrap/archive || handle_error "Failed to change to Rails directory"

# Run gem setup script
log "Setting up gems..."
if [ -f "setup_gems.rb" ]; then
    ruby setup_gems.rb || handle_error "Failed to run gem setup script"
else
    log "setup_gems.rb not found, skipping gem setup"
fi

# Install gems using a simpler approach
log "Installing gems..."
# Clear any existing bundle config
rm -rf ~/.bundle || true
rm -rf .bundle || true

# Set bundle environment
export BUNDLE_PATH="/usr/local/bundle"
export BUNDLE_APP_CONFIG="/usr/local/bundle"

# Try bundle install with a simpler approach
log "Installing gems with bundle..."
if bundle install --retry=3; then
    log "Gems installed successfully"
else
    log "Bundle install failed, trying alternative approach..."
    # Try installing gems directly
    gem install bundler
    bundle install --retry=3 || handle_error "Failed to install gems"
fi

# Verify bundle installation
log "Verifying bundle installation..."
if ! bundle check; then
    handle_error "Bundle check failed after installation"
fi

# Install Active Storage
log "Installing Active Storage..."
if [ -f "bin/rails" ]; then
    bin/rails active_storage:install || log "Active Storage installation failed (may already be installed)"
else
    log "Rails binary not found, skipping Active Storage installation"
fi

# Create database (ignore errors if it already exists)
log "Creating database..."
if [ -f "bin/rails" ]; then
    bin/rails db:create || log "Database creation failed (may already exist)"
else
    log "Rails binary not found, skipping database creation"
fi

# Run migrations
log "Running migrations..."
if [ -f "bin/rails" ]; then
    bin/rails db:migrate || handle_error "Database migration failed"
else
    log "Rails binary not found, skipping migrations"
fi

# Install Pundit
log "Installing Pundit..."
if [ -f "bin/rails" ]; then
    bin/rails generate pundit:install || log "Pundit installation failed (may already be installed)"
else
    log "Rails binary not found, skipping Pundit installation"
fi

# Install Importmap
log "Installing Importmap..."
if [ -f "bin/rails" ]; then
    bin/rails importmap:install || log "Importmap installation failed (may already be installed)"
else
    log "Rails binary not found, skipping Importmap installation"
fi

# Pin Turbo Rails
log "Pinning Turbo Rails..."
if [ -f "bin/importmap" ]; then
    bin/importmap pin @hotwired/turbo-rails || log "Turbo Rails pinning failed"
else
    log "Importmap binary not found, skipping Turbo Rails pinning"
fi

# Seed database
log "Seeding database..."
if [ -f "bin/rails" ]; then
    bin/rails db:seed || log "Database seeding failed (may not be required)"
else
    log "Rails binary not found, skipping database seeding"
fi

log "Rails setup completed successfully!"
log "Ruby version: $RUBY_VERSION"
log "Bundle path: $BUNDLE_PATH" 