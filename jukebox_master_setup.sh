#!/bin/bash

# Master Jukebox Setup Script
# This script sets up the complete jukebox system

set -e

echo "🎵 Master Jukebox Setup"
echo "======================="

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
if [ ! -f "docker-compose.yml" ]; then
    print_error "docker-compose.yml not found. Please run this script from the project root."
    exit 1
fi

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
print_status "Checking prerequisites..."

if ! command_exists ruby; then
    print_error "Ruby is not installed. Please install Ruby 3.3.8 or later."
    exit 1
fi

if ! command_exists bundle; then
    print_error "Bundler is not installed. Please install bundler."
    exit 1
fi

if ! command_exists python3; then
    print_error "Python 3 is not installed. Please install Python 3."
    exit 1
fi

if ! command_exists pip3; then
    print_error "pip3 is not installed. Please install pip3."
    exit 1
fi

print_success "Prerequisites check passed"

# Step 1: Set up Rails jukebox
print_status "Step 1: Setting up Rails jukebox..."
cd jukebox
chmod +x jukebox_setup_rails.sh
./jukebox_setup_rails.sh
cd ..

# Step 2: Set up Python audio player
print_status "Step 2: Setting up Python audio player..."
chmod +x jukebox_setup.sh
./jukebox_setup.sh

# Step 3: Start services
print_status "Step 3: Starting services..."

# Start Redis if not running
if ! systemctl is-active --quiet redis-server; then
    print_status "Starting Redis..."
    sudo systemctl start redis-server
    sudo systemctl enable redis-server
fi

# Start MPD if not running
if ! systemctl is-active --quiet mpd; then
    print_status "Starting MPD..."
    sudo systemctl start mpd
    sudo systemctl enable mpd
fi

# Start jukebox player
print_status "Starting jukebox player..."
sudo systemctl start jukebox-player
sudo systemctl enable jukebox-player

print_success "All services started!"

# Step 4: Verify setup
print_status "Step 4: Verifying setup..."

# Check Redis
if redis-cli ping > /dev/null 2>&1; then
    print_success "Redis is running"
else
    print_error "Redis is not responding"
fi

# Check MPD
if mpc status > /dev/null 2>&1; then
    print_success "MPD is running"
else
    print_error "MPD is not responding"
fi

# Check jukebox player
if systemctl is-active --quiet jukebox-player; then
    print_success "Jukebox player is running"
else
    print_error "Jukebox player is not running"
fi

print_success "Jukebox system setup complete!"
echo ""
print_status "🎵 Your jukebox is ready!"
echo ""
print_status "Next steps:"
echo "1. Start the Rails server: cd jukebox && bin/rails server -p 3001"
echo "2. Visit the jukebox interface: http://localhost:3001/jukebox/status"
echo "3. Configure playlists in the admin interface"
echo "4. Add songs to the queue and start playing!"
echo ""
print_status "Useful URLs:"
echo "- Jukebox Status: http://localhost:3001/jukebox/status"
echo "- API Status: http://localhost:3001/api/jukebox/status"
echo "- API Health: http://localhost:3001/api/jukebox/health"
echo ""
print_status "Useful commands:"
echo "- Rails console: cd jukebox && bin/rails console"
echo "- Player logs: sudo journalctl -u jukebox-player -f"
echo "- Rails logs: cd jukebox && tail -f log/development.log"
echo "- MPD control: mpc status, mpc play, mpc pause"
echo "- Redis queue: redis-cli llen jukebox:queue"
echo ""
print_status "Troubleshooting:"
echo "- Check service status: sudo systemctl status jukebox-player"
echo "- Restart player: sudo systemctl restart jukebox-player"
echo "- Check logs: sudo journalctl -u jukebox-player -f" 