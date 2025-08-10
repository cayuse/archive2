#!/bin/bash

# Jukebox Deployment Script
# This script deploys the Jukebox application with Docker and Apache2

set -e

echo "🎵 Jukebox Deployment Script"
echo "============================"

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

# Check prerequisites
print_status "Checking prerequisites..."

if ! command -v docker >/dev/null 2>&1; then
    print_error "Docker is required but not installed"
    exit 1
fi

if ! command -v docker-compose >/dev/null 2>&1; then
    print_error "Docker Compose is required but not installed"
    exit 1
fi

print_success "Prerequisites check passed"

# Check for required environment variables
if [ -z "$RAILS_MASTER_KEY" ]; then
    print_error "RAILS_MASTER_KEY environment variable is required"
    print_status "Set it with: export RAILS_MASTER_KEY=your_master_key_here"
    exit 1
fi

# Check for Archive dependencies
print_status "Checking Archive dependencies..."

# Check if Archive is running
if ! curl -f http://localhost:3000/up > /dev/null 2>&1; then
    print_error "Archive is not running on localhost:3000"
    print_status "Please deploy Archive first: cd ../archive && ./deploy.sh"
    exit 1
fi

print_success "Archive is running and accessible"

# Check for Archive server URL
if [ -z "$ARCHIVE_SERVER_URL" ]; then
    print_warning "ARCHIVE_SERVER_URL not set, using default http://localhost:3000"
    export ARCHIVE_SERVER_URL=http://localhost:3000
fi

# Check for Archive database connection
if [ -z "$POSTGRES_PASSWORD" ]; then
    print_warning "POSTGRES_PASSWORD not set, using default 'password'"
    export POSTGRES_PASSWORD=password
fi

# Set Archive service connection details
export ARCHIVE_DB_HOST=localhost
export ARCHIVE_DB_PORT=5432
export ARCHIVE_REDIS_HOST=localhost
export ARCHIVE_REDIS_PORT=6379
export ARCHIVE_STORAGE_PATH="../archive/storage"

print_status "Using Archive services:"
print_status "  Database: $ARCHIVE_DB_HOST:$ARCHIVE_DB_PORT"
print_status "  Redis: $ARCHIVE_REDIS_HOST:$ARCHIVE_REDIS_PORT"
print_status "  Storage: $ARCHIVE_STORAGE_PATH"

# Build and start services
print_status "Building and starting Jukebox services..."
docker-compose up -d --build

# Wait for services to be ready
print_status "Waiting for services to be ready..."
sleep 30

# Check if jukebox is responding
if curl -f http://localhost:3001/api/jukebox/health > /dev/null 2>&1; then
    print_success "Jukebox is running successfully"
else
    print_error "Jukebox is not responding. Check logs with: docker-compose logs"
    exit 1
fi

# Apache2 setup
print_status "Setting up Apache2 configuration..."

# Check if Apache2 is installed
if ! command -v apache2ctl >/dev/null 2>&1; then
    print_warning "Apache2 not installed. Installing..."
    sudo apt update
    sudo apt install -y apache2 libapache2-mod-proxy-html
fi

# Enable required Apache2 modules
print_status "Enabling Apache2 modules..."
sudo a2enmod proxy
sudo a2enmod proxy_http
sudo a2enmod headers
sudo a2enmod deflate
sudo a2enmod expires

# Copy Apache2 configuration
print_status "Installing Apache2 configuration..."
sudo cp apache2-jukebox.conf /etc/apache2/sites-available/jukebox.conf

# Enable the site
sudo a2ensite jukebox

# Test Apache2 configuration
if sudo apache2ctl configtest; then
    print_success "Apache2 configuration is valid"
else
    print_error "Apache2 configuration has errors"
    exit 1
fi

# Restart Apache2
print_status "Restarting Apache2..."
sudo systemctl restart apache2

print_success "Jukebox deployment completed!"
echo ""
print_status "Next steps:"
echo "1. Update your DNS to point jukebox.yourdomain.com to this server"
echo "2. Configure SSL certificates for HTTPS"
echo "3. Access your jukebox at: http://jukebox.yourdomain.com"
echo "4. Ensure Archive server is accessible at: $ARCHIVE_SERVER_URL"
echo ""
print_status "Useful commands:"
echo "- View logs: docker-compose logs -f"
echo "- Stop services: docker-compose down"
echo "- Update: git pull && docker-compose up -d --build"
echo "- Check sync status: curl http://localhost:3001/api/jukebox/sync" 