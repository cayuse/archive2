#!/bin/bash

# Archive Deployment Script
# This script deploys the Archive application with Docker and Apache2

set -e

echo "🎵 Archive Deployment Script"
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

if ! docker compose version >/dev/null 2>&1; then
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

# Optional: Set PostgreSQL password
if [ -z "$POSTGRES_PASSWORD" ]; then
    print_warning "POSTGRES_PASSWORD not set, using default 'password'"
    export POSTGRES_PASSWORD=password
fi

# Optional: Set SMTP configuration for email delivery
if [ -z "$SMTP_HOST" ]; then
    print_warning "SMTP_HOST not set, using default 'localhost'"
    export SMTP_HOST=localhost
fi

if [ -z "$SMTP_PORT" ]; then
    print_warning "SMTP_PORT not set, using default '587'"
    export SMTP_PORT=587
fi

if [ -z "$SMTP_DOMAIN" ]; then
    if [ -n "$APP_HOST" ]; then
        export SMTP_DOMAIN="$APP_HOST"
        print_status "Using APP_HOST as SMTP_DOMAIN: $SMTP_DOMAIN"
    else
        print_warning "SMTP_DOMAIN not set, using default 'musicarchive.com'"
        export SMTP_DOMAIN=musicarchive.com
    fi
fi

# Note: SMTP_USERNAME and SMTP_PASSWORD are optional (for unauthenticated SMTP)
if [ -n "$SMTP_USERNAME" ] && [ -n "$SMTP_PASSWORD" ]; then
    print_status "SMTP authentication enabled with username: $SMTP_USERNAME"
else
    print_warning "SMTP authentication not configured - using unauthenticated SMTP"
fi

# Optional: Set storage paths
if [ -z "$HOST_STORAGE_PATH" ]; then
    print_warning "HOST_STORAGE_PATH not set, using default './storage'"
    export HOST_STORAGE_PATH="./storage"
fi

# Create storage directory if it doesn't exist
if [ ! -d "$HOST_STORAGE_PATH" ]; then
    print_status "Creating storage directory: $HOST_STORAGE_PATH"
    mkdir -p "$HOST_STORAGE_PATH"
fi

# Optional: Set PostgreSQL data directory
if [ -z "$POSTGRES_DATA_PATH" ]; then
    print_warning "POSTGRES_DATA_PATH not set, using default './postgres_data'"
    export POSTGRES_DATA_PATH="./postgres_data"
fi

# Create PostgreSQL data directory if it doesn't exist
if [ ! -d "$POSTGRES_DATA_PATH" ]; then
    print_status "Creating PostgreSQL data directory: $POSTGRES_DATA_PATH"
    mkdir -p "$POSTGRES_DATA_PATH"
fi

# Build and start services
print_status "Building and starting Archive services..."
docker compose up -d --build

# Wait for services to be ready
print_status "Waiting for services to be ready..."
sleep 30

# Check if archive is responding
if curl -f http://localhost:3000/up > /dev/null 2>&1; then
    print_success "Archive is running successfully"
else
    print_error "Archive is not responding. Check logs with: docker compose logs"
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
sudo cp apache2-archive.conf /etc/apache2/sites-available/archive.conf

# Enable the site
sudo a2ensite archive

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

print_success "Archive deployment completed!"
echo ""
print_status "Next steps:"
echo "1. Update your DNS to point archive.yourdomain.com to this server"
echo "2. Configure SSL certificates for HTTPS"
echo "3. Access your archive at: http://archive.yourdomain.com"
echo "4. Default admin login: admin@musicarchive.com / admin123"
echo ""
print_warning "IMPORTANT: Change the default admin password immediately!"
echo ""
print_status "Useful commands:"
echo "- View logs: docker compose logs -f"
echo "- Stop services: docker compose down"
echo "- Update: git pull && docker compose up -d --build" 