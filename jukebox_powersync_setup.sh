#!/bin/bash

# PowerSync Jukebox System Setup Script
# This script sets up the complete PowerSync-based jukebox system

set -e

echo "🎵 PowerSync Jukebox System Setup"
echo "================================="

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

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   print_error "This script should not be run as root"
   exit 1
fi

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
print_status "Checking prerequisites..."

if ! command_exists docker; then
    print_error "Docker is required but not installed. Please install Docker first."
    exit 1
fi

if ! command_exists docker-compose; then
    print_error "Docker Compose is required but not installed. Please install Docker Compose first."
    exit 1
fi

if ! command_exists ruby; then
    print_error "Ruby is required but not installed. Please install Ruby 3.3.8 or later."
    exit 1
fi

print_success "Prerequisites check passed"

# Step 1: Set up Archive Server
print_status "Step 1: Setting up Archive Server with PowerSync..."

cd archive

# Install PowerSync gem
print_status "Installing PowerSync gem..."
bundle install

# Set up PowerSync
print_status "Setting up PowerSync configuration..."
if [ ! -f "config/initializers/powersync.rb" ]; then
    print_error "PowerSync configuration not found. Please ensure the PowerSync initializer is created."
    exit 1
fi

# Start archive server
print_status "Starting archive server..."
docker-compose up -d

# Wait for archive to be ready
print_status "Waiting for archive server to be ready..."
sleep 30

# Check if archive is responding
if curl -f http://localhost:3000/up > /dev/null 2>&1; then
    print_success "Archive server is running"
else
    print_error "Archive server is not responding. Check docker-compose logs."
    exit 1
fi

cd ..

# Step 2: Set up Jukebox
print_status "Step 2: Setting up Jukebox with PowerSync..."

cd jukebox

# Install gems
print_status "Installing jukebox gems..."
bundle install

# Set up SQLite database
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
    print_success "Created .env file"
fi

# Make scripts executable
print_status "Setting up executable permissions..."
chmod +x bin/*

cd ..

# Step 3: Set up Audio System
print_status "Step 3: Setting up Audio System..."

# Install system dependencies
print_status "Installing system dependencies..."
sudo apt update
sudo apt install -y \
    mpd \
    mpc \
    redis-server \
    python3 \
    python3-pip \
    python3-venv \
    ffmpeg \
    libmpdclient-dev \
    build-essential \
    pkg-config

# Start and enable services
print_status "Starting and enabling services..."
sudo systemctl enable mpd
sudo systemctl start mpd
sudo systemctl enable redis-server
sudo systemctl start redis-server

# Configure MPD for jukebox
print_status "Configuring MPD for jukebox..."
sudo tee /etc/mpd-jukebox.conf > /dev/null << 'EOF'
# Jukebox-specific MPD configuration
music_directory         "/var/lib/jukebox/cache"
playlist_directory      "/var/lib/jukebox/playlists"
db_file                 "/var/lib/jukebox/mpd/tag_cache"
log_file                "/var/lib/jukebox/logs/mpd.log"
pid_file                "/var/lib/jukebox/mpd/pid"
state_file              "/var/lib/jukebox/mpd/state"
sticker_file            "/var/lib/jukebox/mpd/sticker.sql"

# Audio output configuration
audio_output {
    type            "alsa"
    name            "Jukebox Output"
    device          "default"
    mixer_type      "hardware"
    mixer_device    "default"
    mixer_control   "PCM"
    mixer_index     "0"
}

# Crossfade settings
audio_buffer_size      "8192"
buffer_before_play     "25%"
crossfade_time         "3"
EOF

# Create jukebox directories
print_status "Creating jukebox directories..."
sudo mkdir -p /var/lib/jukebox/cache
sudo mkdir -p /var/lib/jukebox/logs
sudo mkdir -p /var/lib/jukebox/config
sudo chown -R $USER:$USER /var/lib/jukebox

# Set up Python audio player
print_status "Setting up Python audio player..."
cd jukebox/audio_player

if [ ! -d "venv" ]; then
    python3 -m venv venv
fi

source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

# Create player configuration
print_status "Creating player configuration..."
tee config.json > /dev/null << 'EOF'
{
    "mpd_host": "localhost",
    "mpd_port": 6600,
    "mpd_password": null,
    "redis_host": "localhost",
    "redis_port": 6379,
    "redis_db": 0,
    "jukebox_api_url": "http://localhost:3001/api",
    "cache_directory": "/var/lib/jukebox/cache",
    "crossfade_duration": 3,
    "volume": 80,
    "retry_attempts": 3,
    "retry_delay": 5
}
EOF

# Make player script executable
chmod +x player.py

# Create systemd service for jukebox player
print_status "Creating systemd service for jukebox player..."
sudo tee /etc/systemd/system/jukebox-player.service > /dev/null << EOF
[Unit]
Description=Jukebox Audio Player
After=network.target mpd.service redis-server.service
Wants=mpd.service redis-server.service

[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=$(pwd)
Environment=PATH=$(pwd)/venv/bin
ExecStart=$(pwd)/venv/bin/python player.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable service
print_status "Enabling jukebox player service..."
sudo systemctl daemon-reload
sudo systemctl enable jukebox-player

cd ../..

# Step 4: Test the System
print_status "Step 4: Testing the system..."

# Test Redis connection
print_status "Testing Redis connection..."
if redis-cli ping > /dev/null 2>&1; then
    print_success "Redis connection successful"
else
    print_error "Redis connection failed"
    exit 1
fi

# Test MPD connection
print_status "Testing MPD connection..."
if mpc status > /dev/null 2>&1; then
    print_success "MPD connection successful"
else
    print_error "MPD connection failed"
    exit 1
fi

# Test archive connection
print_status "Testing archive connection..."
if curl -f http://localhost:3000/up > /dev/null 2>&1; then
    print_success "Archive connection successful"
else
    print_error "Archive connection failed"
    exit 1
fi

print_success "PowerSync Jukebox System setup complete!"
echo ""
print_status "System Status:"
echo "- Archive Server: http://localhost:3000"
echo "- Jukebox Web Interface: http://localhost:3001"
echo "- Jukebox API: http://localhost:3001/api/jukebox"
echo "- Redis: localhost:6379"
echo "- MPD: localhost:6600"
echo ""
print_status "Next steps:"
echo "1. Start the jukebox Rails server:"
echo "   cd jukebox && bin/rails server -p 3001"
echo ""
echo "2. Start the jukebox player:"
echo "   sudo systemctl start jukebox-player"
echo ""
echo "3. Check system status:"
echo "   curl http://localhost:3001/api/jukebox/health"
echo ""
echo "4. Force initial sync:"
echo "   curl -X POST http://localhost:3001/api/jukebox/sync/force"
echo ""
print_warning "Important notes:"
echo "- The jukebox will sync music metadata from the archive"
echo "- Songs will be downloaded on-demand when added to queue"
echo "- Check the web interface at http://localhost:3001 for controls"
echo "- Monitor sync status at http://localhost:3001/sync" 