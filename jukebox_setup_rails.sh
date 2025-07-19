#!/bin/bash

# Jukebox Rails Setup Script (PowerSync Edition)
# This script sets up the Rails jukebox application with PowerSync

set -e

echo "🎵 Jukebox Rails Setup (PowerSync Edition)"
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're in the right directory
if [ ! -f "Gemfile" ]; then
    print_error "Gemfile not found. Please run this script from the jukebox directory."
    exit 1
fi

# Install gems
print_status "Installing Ruby gems..."
bundle install

# Set up database
print_status "Setting up SQLite database..."
bin/rails db:create
bin/rails db:migrate

# Set up Active Storage
print_status "Setting up Active Storage..."
bin/rails active_storage:install
bin/rails db:migrate

# Set up background jobs
print_status "Setting up background jobs..."
bin/rails solid_queue:install
bin/rails db:migrate

# Create cache directories
print_status "Creating cache directories..."
mkdir -p storage/cached_songs
mkdir -p log

# Set up credentials if needed
if [ ! -f "config/master.key" ]; then
    print_status "Setting up Rails credentials..."
    echo "changeme" > config/master.key
    print_warning "Created default master key. You should change this in production."
fi

# Set up environment variables
print_status "Setting up environment variables..."
if [ ! -f ".env" ]; then
    cat > .env << 'EOF'
# Jukebox Configuration
RAILS_ENV=development
RAILS_MASTER_KEY=changeme

# Archive Server Configuration
ARCHIVE_SERVER_URL=http://localhost:3000
ARCHIVE_API_KEY=

# Jukebox Client Configuration
JUKEBOX_CLIENT_ID=jukebox-1

# Redis Configuration
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_DB=0

# PowerSync Configuration
POWERSYNC_ENABLED=true
POWERSYNC_SYNC_INTERVAL=30
EOF
    print_success "Created .env file with default configuration"
fi

# Make scripts executable
print_status "Setting up executable permissions..."
chmod +x bin/*

print_success "Jukebox Rails setup complete!"
echo ""
print_status "Next steps:"
echo "1. Configure the archive server URL in .env file"
echo "2. Start the Rails server: bin/rails server -p 3001"
echo "3. Set up the Python audio player: ../jukebox_setup.sh"
echo "4. Start PowerSync synchronization"
echo "5. Configure playlists in the admin interface"
echo "6. Start the jukebox player: sudo systemctl start jukebox-player"
echo ""
print_status "Useful commands:"
echo "- Rails console: bin/rails console"
echo "- Database console: bin/rails dbconsole"
echo "- Check sync status: curl http://localhost:3001/api/jukebox/sync"
echo "- Check system health: curl http://localhost:3001/api/jukebox/health"
echo ""
print_warning "Remember to:"
echo "- Update ARCHIVE_SERVER_URL in .env to point to your archive server"
echo "- Set up PowerSync authentication if required"
echo "- Configure Redis connection settings" 