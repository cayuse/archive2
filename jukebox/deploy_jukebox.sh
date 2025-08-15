#!/bin/bash

# =============================================================================
# JUKEBOX DEPLOYMENT SCRIPT - DEPLOYMENT ORDER IS CRITICAL
# =============================================================================
# 
# ⚠️  DEPLOYMENT ORDER (DO NOT CHANGE) ⚠️
# 
# 1. FIRST: Deploy Archive (creates PostgreSQL, Redis, network)
# 2. SECOND: Deploy Jukebox (connects to Archive's services)
#
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}=============================================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}=============================================================================${NC}"
}

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

print_header "JUKEBOX DEPLOYMENT SCRIPT"
echo ""

# Check if we're in the right directory
if [ ! -f "docker-compose.yml" ]; then
    print_error "This script must be run from the jukebox directory"
    exit 1
fi

# Check if Archive is running
print_status "Step 1: Verifying Archive deployment..."

if ! docker ps | grep -q "archive2-archive-1"; then
    print_error "Archive is not running!"
    echo ""
    print_error "You MUST deploy Archive FIRST:"
    echo "  cd ../archive"
    echo "  docker compose up -d"
    echo "  cd ../jukebox"
    echo ""
    print_error "Then run this script again."
    exit 1
fi

print_success "✓ Archive is running"

# Check Archive health
print_status "Step 2: Checking Archive health..."
if curl -f http://localhost:3000/up > /dev/null 2>&1; then
    print_success "✓ Archive is healthy"
else
    print_error "Archive is not responding!"
    print_error "Wait for Archive to fully start up, then try again."
    exit 1
fi

# Check Docker network
print_status "Step 3: Checking Docker network..."
if docker network ls | grep -q "archive2_default"; then
    print_success "✓ Archive network exists"
else
    print_error "Archive network not found!"
    print_error "This should be created automatically when Archive starts."
    exit 1
fi

# Check environment variables
print_status "Step 4: Checking environment variables..."
REQUIRED_VARS=("RAILS_MASTER_KEY" "POSTGRES_PASSWORD" "HOST_STORAGE_PATH")
MISSING_VARS=()

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        MISSING_VARS+=("$var")
    fi
done

if [ ${#MISSING_VARS[@]} -eq 0 ]; then
    print_success "✓ All required environment variables are set"
else
    print_error "Missing required environment variables:"
    for var in "${MISSING_VARS[@]}"; do
        print_error "  - $var"
    done
    print_error "Please set these before deploying Jukebox"
    exit 1
fi

# Check storage path
print_status "Step 5: Checking storage path..."
if [ -d "$HOST_STORAGE_PATH" ]; then
    print_success "✓ Storage path exists: $HOST_STORAGE_PATH"
    
    if [ -r "$HOST_STORAGE_PATH" ]; then
        print_success "✓ Storage path is readable"
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
print_header "DEPLOYING JUKEBOX"
echo ""

print_status "Building and starting Jukebox..."
print_status "This will connect to Archive's PostgreSQL at db:5432"
print_status "This will connect to Archive's Redis at redis:6379"
print_status "This will connect to host MPD at localhost:6600"
echo ""

# Deploy Jukebox
docker compose up -d --build

echo ""
print_success "Jukebox deployment started!"
echo ""

print_status "Checking Jukebox health..."
sleep 10  # Give it time to start

if curl -f http://localhost:3001/api/jukebox/health > /dev/null 2>&1; then
    print_success "✓ Jukebox is healthy"
else
    print_warning "Jukebox may still be starting up..."
    print_status "Check logs: docker compose logs -f jukebox"
fi

echo ""
print_header "DEPLOYMENT COMPLETE"
echo ""
print_success "Jukebox is now running and connected to Archive!"
echo ""
print_status "Access points:"
echo "  - Jukebox web interface: http://localhost:3001"
echo "  - Jukebox health: http://localhost:3001/api/jukebox/health"
echo "  - Player status: http://localhost:3001/api/player/status"
echo ""
print_status "Useful commands:"
echo "  - View logs: docker compose logs -f jukebox"
echo "  - Check status: docker compose ps"
echo "  - Restart: docker compose restart jukebox"
echo "  - Stop: docker compose down"
echo ""
print_status "Remember: Jukebox depends on Archive being running!"
echo "  - Archive PostgreSQL: db:5432 (Docker network)"
echo "  - Archive Redis: redis:6379 (Docker network)"
echo "  - Host MPD: localhost:6600 (host network)"
echo ""
