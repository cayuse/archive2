#!/bin/bash

# =============================================================================
# JUKEBOX DEPENDENCY CHECKER
# =============================================================================
# 
# This script checks if Archive is running and accessible before deploying Jukebox
# Run this BEFORE trying to deploy Jukebox
#
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

echo "============================================================================="
echo "JUKEBOX DEPENDENCY CHECKER"
echo "============================================================================="
echo ""

# Check if we're in the right directory
if [ ! -f "docker-compose.yml" ]; then
    print_error "This script must be run from the jukebox directory"
    exit 1
fi

# Check if Archive is running
print_status "Checking Archive deployment..."

# Check Archive container status
if docker ps | grep -q "archive2-archive-1"; then
    print_success "Archive container is running"
else
    print_error "Archive container is not running!"
    print_error "Please deploy Archive first:"
    print_error "  cd ../archive && docker compose up -d"
    exit 1
fi

# Check Archive health
print_status "Checking Archive health..."
if curl -f http://localhost:3000/up > /dev/null 2>&1; then
    print_success "Archive is responding at http://localhost:3000/up"
else
    print_error "Archive is not responding at http://localhost:3000/up"
    print_error "Archive may still be starting up. Wait a moment and try again."
    exit 1
fi

# Check PostgreSQL (via Docker network)
print_status "Checking PostgreSQL (via Docker network)..."
if docker exec archive2-db-1 pg_isready -U postgres > /dev/null 2>&1; then
    print_success "PostgreSQL is ready"
else
    print_error "PostgreSQL is not ready!"
    exit 1
fi

# Check Redis (via Docker network)
print_status "Checking Redis (via Docker network)..."
if docker exec archive2-redis-1 redis-cli ping | grep -q "PONG"; then
    print_success "Redis is responding"
else
    print_error "Redis is not responding!"
    exit 1
fi

# Check Docker network
print_status "Checking Docker network..."
if docker network ls | grep -q "archive2_default"; then
    print_success "Archive network exists: archive2_default"
else
    print_error "Archive network 'archive2_default' not found!"
    print_error "This network should be created when Archive starts"
    exit 1
fi

# Check MPD
print_status "Checking host MPD..."
if command -v mpc > /dev/null 2>&1; then
    if mpc status > /dev/null 2>&1; then
        print_success "Host MPD is running and accessible"
    else
        print_warning "MPD is installed but not responding. Check: sudo systemctl status mpd"
    fi
else
    print_warning "MPC not found. Install MPD: sudo apt install mpd mpc"
fi

# Check environment variables
print_status "Checking environment variables..."

REQUIRED_VARS=("RAILS_MASTER_KEY" "POSTGRES_PASSWORD" "HOST_STORAGE_PATH")
MISSING_VARS=()

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        MISSING_VARS+=("$var")
    fi
done

if [ ${#MISSING_VARS[@]} -eq 0 ]; then
    print_success "All required environment variables are set"
else
    print_error "Missing required environment variables:"
    for var in "${MISSING_VARS[@]}"; do
        print_error "  - $var"
    done
    print_error "Please set these before deploying Jukebox"
    exit 1
fi

# Check storage path
print_status "Checking storage path..."
if [ -d "$HOST_STORAGE_PATH" ]; then
    print_success "Storage path exists: $HOST_STORAGE_PATH"
    
    # Check if it's readable
    if [ -r "$HOST_STORAGE_PATH" ]; then
        print_success "Storage path is readable"
    else
        print_error "Storage path is not readable!"
        print_error "Check permissions: ls -la $HOST_STORAGE_PATH"
        exit 1
    fi
else
    print_error "Storage path does not exist: $HOST_STORAGE_PATH"
    print_error "Please ensure Archive storage is properly set up"
    exit 1
fi

echo ""
echo "============================================================================="
print_success "ALL DEPENDENCIES CHECKED - READY TO DEPLOY JUKEBOX!"
echo "============================================================================="
echo ""
echo "Next steps:"
echo "1. Deploy Jukebox: docker compose up -d"
echo "2. Check logs: docker compose logs -f jukebox"
echo "3. Test health: curl http://localhost:3001/api/jukebox/health"
echo "4. Test player: curl http://localhost:3001/api/player/health"
echo ""
echo "If you encounter issues:"
echo "- Check logs: docker compose logs jukebox"
echo "- Verify MPD: mpc status"
echo "- Check Archive: curl http://localhost:3000/up"
echo ""
