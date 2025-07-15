#!/bin/bash

# Rails setup script for devcontainer
# This script handles all the Rails initialization steps

set -e

echo "Starting Rails setup..."

# Install system dependencies
echo "Installing system dependencies..."
sudo apt update
sudo apt install -y libpq-dev

# Change to the Rails application directory
cd /workspaces/dockercrap/archive

# Run gem setup script
echo "Setting up gems..."
ruby setup_gems.rb

# Install gems
echo "Installing gems..."
# Clear gem cache and try multiple approaches
rm -rf ~/.cache/gem/specs || true
rm -rf vendor/bundle || true

# Try bundle install with retries
for i in {1..3}; do
  echo "Attempt $i: Installing gems..."
  if bundle install --retry=3; then
    echo "Gems installed successfully"
    break
  else
    echo "Bundle install failed, trying to update gem sources..."
    gem sources --clear-all
    gem sources -a https://rubygems.org/
    if [ $i -eq 3 ]; then
      echo "Failed to install gems after 3 attempts"
      exit 1
    fi
  fi
done

# Install Active Storage
echo "Installing Active Storage..."
bin/rails active_storage:install

# Create database (ignore errors if it already exists)
echo "Creating database..."
bin/rails db:create || true

# Run migrations
echo "Running migrations..."
bin/rails db:migrate

# Install Pundit
echo "Installing Pundit..."
bin/rails generate pundit:install

# Install Importmap
echo "Installing Importmap..."
bin/rails importmap:install

# Pin Turbo Rails
echo "Pinning Turbo Rails..."
bin/importmap pin @hotwired/turbo-rails

# Seed database
echo "Seeding database..."
bin/rails db:seed

echo "Rails setup completed successfully!" 