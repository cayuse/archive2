#!/bin/bash

# Archive Jukebox Migration Script
# This script runs database migrations in the Archive application
# Usage: ./run_migration.sh [environment]
# Default environment is 'production'

set -e  # Exit on any error

# Default to production environment
ENVIRONMENT=${1:-production}

echo "🔄 Running Archive database migrations..."
echo "📍 Environment: $ENVIRONMENT"
echo "📁 Working directory: $(pwd)"

# Check if we're in the right directory
if [ ! -f "archive/docker-compose.yml" ]; then
    echo "❌ Error: docker-compose.yml not found in archive/ directory"
    echo "💡 Make sure you're running this from the archive2 root directory"
    exit 1
fi

# Change to archive directory
cd archive

# Check if docker compose is available
if ! command -v docker &> /dev/null; then
    echo "❌ Error: Docker is not installed or not in PATH"
    exit 1
fi

# Check if containers are running
echo "🔍 Checking if Archive containers are running..."
if ! docker compose ps | grep -q "Up"; then
    echo "❌ Error: Archive containers are not running"
    echo "💡 Start the containers first with: docker compose up -d"
    exit 1
fi

# Run the migration
echo "🚀 Running migration..."
docker compose exec archive bin/rails db:migrate RAILS_ENV=$ENVIRONMENT

echo "✅ Migration completed successfully!"
echo "🎵 Archive Jukebox is ready to go!"
