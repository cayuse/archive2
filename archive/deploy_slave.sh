#!/bin/bash

# Archive Slave Deployment Script
# This script deploys a slave Archive system with Bucardo replication

set -e

echo "🎵 Archive Slave Deployment Script"
echo "=================================="

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
    print_error "This script must be run from the archive directory"
    exit 1
fi

# Check if environment is sourced
if [ -z "$ARCHIVE_ROLE" ] || [ "$ARCHIVE_ROLE" != "slave" ]; then
    print_error "Please source the environment configuration first:"
    print_status "   source ../temp_corrected_exports.sh"
    print_status "Current ARCHIVE_ROLE: ${ARCHIVE_ROLE:-'not set'}"
    exit 1
fi

print_success "Environment loaded: $ARCHIVE_ROLE"
print_status "App Host: $APP_HOST"
print_status "Master DB: $MASTER_DB_HOST:$MASTER_DB_PORT"
print_status "Sync Frequency: every $BUCARDO_SYNC_FREQUENCY minute(s)"

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    print_error "Docker is not running"
    exit 1
fi

print_success "Docker is running"

# Check if required environment variables are set
required_vars=(
    "POSTGRES_PASSWORD"
    "POSTGRES_DATA_PATH"
    "HOST_STORAGE_PATH"
    "RAILS_MASTER_KEY"
    "MASTER_DB_HOST"
    "MASTER_DB_USER"
    "MASTER_DB_PASS"
    "BUCARDO_SYNC_FREQUENCY"
)

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        print_error "Required environment variable $var is not set"
        exit 1
    fi
done

print_success "All required environment variables are set"

# Create required directories
print_status "Creating required directories..."
mkdir -p "$POSTGRES_DATA_PATH"
mkdir -p "$HOST_STORAGE_PATH"

# Set proper permissions
print_status "Setting directory permissions..."
sudo chown -R 999:999 "$POSTGRES_DATA_PATH" 2>/dev/null || true
sudo chown -R 1000:1000 "$HOST_STORAGE_PATH" 2>/dev/null || true

print_success "Directories created and permissions set"

# Build and start the database first
print_status "Building and starting PostgreSQL database..."
docker compose build db
docker compose up -d db

# Wait for database to be healthy
print_status "Waiting for database to be ready..."
until docker compose exec db pg_isready -U postgres; do
    print_status "   Database not ready, waiting..."
    sleep 5
done

# Additional wait to ensure database is fully initialized
print_status "Ensuring database is fully initialized..."
sleep 10

# Test actual database connection and basic operations
print_status "Testing database connectivity..."
until docker compose exec db psql -U postgres -c "SELECT 1;" >/dev/null 2>&1; do
    print_status "   Database not responding to queries, waiting..."
    sleep 5
done

print_success "Database is ready!"

# Run database setup (create database, run migrations)
print_status "Setting up database..."
docker compose exec db psql -U postgres -c "CREATE DATABASE archive_production;" 2>/dev/null || true

# Start the archive application to run migrations
print_status "Starting archive application for migrations..."
docker compose up -d archive

# Wait a bit for the app to fully start
print_status "Waiting for archive application to fully start..."
sleep 15

# Wait for archive to be healthy
print_status "Waiting for archive application to be ready..."
until docker compose exec archive curl -f http://localhost:3000/up 2>/dev/null; do
    print_status "   Archive not ready, waiting..."
    sleep 5
done

print_success "Archive application is ready!"

# Run database migrations
print_status "Running database migrations..."
docker compose exec archive bin/rails db:migrate

print_success "Database migrations complete!"

# Setup Bucardo database and user
print_status "Setting up Bucardo database and user..."
docker compose exec db psql -U postgres -c "DO \$\$ BEGIN CREATE USER bucardo WITH PASSWORD 'bucardo'; EXCEPTION WHEN duplicate_object THEN null; END \$\$;" 2>/dev/null || true
docker compose exec db psql -U postgres -c "CREATE DATABASE bucardo OWNER bucardo;" 2>/dev/null || true
docker compose exec db psql -U postgres -c "ALTER USER bucardo WITH SUPERUSER;" 2>/dev/null || true
docker compose exec db psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE bucardo TO bucardo;" 2>/dev/null || true
docker compose exec db psql -U postgres -d bucardo -c "GRANT ALL PRIVILEGES ON SCHEMA public TO bucardo;" 2>/dev/null || true

# Install Bucardo schema
print_status "Installing Bucardo schema..."
docker compose exec db psql -U bucardo -d bucardo -f /usr/share/bucardo/bucardo.schema 2>/dev/null || true

print_success "Bucardo database setup complete!"

# Bucardo configuration is handled by command line parameters in the container
print_status "Bucardo will use command line parameters for configuration"

# Build and start Bucardo
print_status "Building and starting Bucardo replication service..."
docker compose build bucardo
docker compose up -d bucardo

# Wait for Bucardo to be healthy
print_status "Waiting for Bucardo to be ready..."
until docker compose exec bucardo pg_isready -h db -U bucardo 2>/dev/null; do
    print_status "   Bucardo not ready, waiting..."
    sleep 5
done

print_success "Bucardo is ready!"

# Start remaining services
print_status "Starting remaining services..."
docker compose up -d

# Final status check
print_status "Final status check..."
docker compose ps

echo ""
print_success "Archive Slave deployment completed!"
echo ""
print_status "Next steps:"
echo "1. Check Bucardo logs: docker compose logs bucardo"
echo "2. Verify replication: docker compose exec bucardo bucardo status"
echo "3. Monitor sync: docker compose exec bucardo bucardo list syncs"
echo ""
print_status "Useful commands:"
echo "- View logs: docker compose logs -f"
echo "- Stop services: docker compose down"
echo "- Update: git pull && docker compose up -d --build"
echo ""
print_status "For replication troubleshooting, see BUCARDO_SETUP.md"
