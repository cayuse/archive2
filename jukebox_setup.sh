#!/bin/bash

# Jukebox System Setup Script
# This script sets up the complete jukebox system with MPD, Redis, and Python player

set -e

echo "🎵 Jukebox System Setup"
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

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   print_error "This script should not be run as root"
   exit 1
fi

# Update system packages
print_status "Updating system packages..."
sudo apt update

# Install system dependencies
print_status "Installing system dependencies..."
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

# Configure MPD
print_status "Configuring MPD..."
sudo tee /etc/mpd.conf > /dev/null << 'EOF'
# MPD Configuration for Jukebox
music_directory         "/var/lib/jukebox/cache"
playlist_directory      "/var/lib/mpd/playlists"
db_file                 "/var/lib/mpd/tag_cache"
log_file                "/var/log/mpd/mpd.log"
pid_file                "/var/run/mpd/pid"
state_file              "/var/lib/mpd/state"
sticker_file            "/var/lib/mpd/sticker.sql"

# Audio output configuration
audio_output {
    type            "alsa"
    name            "ALSA Output"
    device          "default"
    mixer_type      "hardware"
    mixer_device    "default"
    mixer_control   "PCM"
    mixer_index     "0"
}

# HTTP stream output (optional)
audio_output {
    type            "httpd"
    name            "HTTP Stream"
    encoder         "lame"
    port            "8000"
    bitrate         "128"
    format          "44100:16:1"
    max_clients     "0"
}

# Crossfade settings
audio_buffer_size      "4096"
buffer_before_play     "25%"
EOF

# Create jukebox directories
print_status "Creating jukebox directories..."
sudo mkdir -p /var/lib/jukebox/cache
sudo mkdir -p /var/lib/jukebox/logs
sudo mkdir -p /var/lib/jukebox/config
sudo chown -R $USER:$USER /var/lib/jukebox

# Set up Python virtual environment
print_status "Setting up Python environment..."
cd jukebox/audio_player
python3 -m venv venv
source venv/bin/activate

# Install Python dependencies
print_status "Installing Python dependencies..."
pip install --upgrade pip
pip install -r requirements.txt

# Create MPD configuration for jukebox
print_status "Creating jukebox-specific MPD config..."
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

# Create configuration file
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

# Reload systemd and enable service
print_status "Enabling jukebox player service..."
sudo systemctl daemon-reload
sudo systemctl enable jukebox-player

# Test MPD connection
print_status "Testing MPD connection..."
if mpc status > /dev/null 2>&1; then
    print_success "MPD connection successful"
else
    print_error "MPD connection failed"
    exit 1
fi

# Test Redis connection
print_status "Testing Redis connection..."
if redis-cli ping > /dev/null 2>&1; then
    print_success "Redis connection successful"
else
    print_error "Redis connection failed"
    exit 1
fi

# Create Rails database migrations
print_status "Setting up Rails database..."
cd ../..
cd jukebox
bin/rails db:create
bin/rails db:migrate

print_success "Jukebox system setup complete!"
echo ""
print_status "Next steps:"
echo "1. Configure playlists in the jukebox web interface"
echo "2. Start the jukebox player: sudo systemctl start jukebox-player"
echo "3. Check status: sudo systemctl status jukebox-player"
echo "4. View logs: sudo journalctl -u jukebox-player -f"
echo ""
print_status "Useful commands:"
echo "- MPD control: mpc play, mpc pause, mpc next, mpc prev"
echo "- Redis queue: redis-cli llen jukebox:queue"
echo "- Player status: redis-cli get jukebox:current_song"
echo ""
print_status "Configuration files:"
echo "- MPD config: /etc/mpd.conf"
echo "- Player config: jukebox/audio_player/config.json"
echo "- Service: /etc/systemd/system/jukebox-player.service" 