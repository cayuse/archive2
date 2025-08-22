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

# Check for Archive dependencies (network only)
print_status "Assuming Archive DB/Redis are reachable on the shared docker network (db/redis)."

# Optional: Force database setup
if [ "${FORCE_DB_SETUP:-false}" = "true" ]; then
    print_status "FORCE_DB_SETUP is enabled - will recreate database"
fi

if [ -z "$POSTGRES_PASSWORD" ]; then
    print_error "POSTGRES_PASSWORD not set"
    exit 1
fi

# Set Archive service connection details
# Prefer Archive's compose network service names; fallback to localhost if not joined
export ARCHIVE_DB_HOST=${ARCHIVE_DB_HOST:-db}
export ARCHIVE_DB_PORT=${ARCHIVE_DB_PORT:-5432}
export ARCHIVE_REDIS_HOST=${ARCHIVE_REDIS_HOST:-redis}
export ARCHIVE_REDIS_PORT=${ARCHIVE_REDIS_PORT:-6379}

# Require absolute storage path (shared var from Archive)
if [ -z "$HOST_STORAGE_PATH" ]; then
  print_error "HOST_STORAGE_PATH not set. Export the same path used by Archive."
  exit 1
fi
case "$HOST_STORAGE_PATH" in
  /*) : ;;
  *) print_error "HOST_STORAGE_PATH must be an absolute path"; exit 1;;
esac

print_status "Using Archive services:"
print_status "  Database: $ARCHIVE_DB_HOST:$ARCHIVE_DB_PORT"
print_status "  Redis: $ARCHIVE_REDIS_HOST:$ARCHIVE_REDIS_PORT"
print_status "  Storage: $HOST_STORAGE_PATH"

# Build and start services
print_status "Building and starting Jukebox services..."
docker compose up -d --build

# One-time database setup on first deploy when jukebox tables don't exist
print_status "Checking jukebox table initialization status..."
JUKEBOX_READY=$(docker compose exec -T jukebox bash -lc "bin/rails runner \"puts ActiveRecord::Base.connection.table_exists?('jukebox_played_songs')\"" 2>/dev/null) || JUKEBOX_READY="false"

if [ "${FORCE_DB_SETUP:-false}" = "true" ] || [ "$JUKEBOX_READY" != "true" ]; then
  print_status "Running jukebox database setup (create/migrate)"
  docker compose exec -T jukebox bash -lc './bin/rails db:migrate'
else
  print_status "Jukebox tables already exist. Skipping setup. (Set FORCE_DB_SETUP=true to override)"
fi

# Wait for services to be ready
print_status "Waiting for services to be ready..."
sleep 30

# Check if jukebox is responding
if curl -f http://localhost:3001/api/jukebox/health > /dev/null 2>&1; then
    print_success "Jukebox is running successfully"
else
    print_error "Jukebox is not responding. Check logs with: docker compose logs"
    exit 1
fi

print_success "Jukebox deployment completed!"
echo ""
print_status "Next steps:"
echo "1. Configure your reverse proxy (nginx/Apache) to proxy 80/443 → 3001"
echo "2. Set up SSL certificates (Let's Encrypt recommended)"
echo "3. Configure your domain DNS to point to this server"
echo "4. Access your jukebox at: http://localhost:3001"
echo "5. Ensure Archive services (db/redis) are reachable on the shared docker network"
echo ""
print_status "Useful commands:"
echo "- View logs: docker compose logs -f"
echo "- Stop services: docker compose down"
echo "- Update: git pull && docker compose up -d --build"
echo "- Check sync status: curl http://localhost:3001/api/jukebox/sync"
echo ""
print_status "For production deployment with nginx/SSL, see DEPLOYMENT_GUIDE.md" 