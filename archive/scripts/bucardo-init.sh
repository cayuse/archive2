#!/bin/bash
set -e

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

echo "Starting Bucardo initialization..."

# Wait for postgres database to be ready first
echo "Waiting for postgres database to be ready..."
until pg_isready -h db -U postgres -d postgres; do
    echo "Postgres database not ready, waiting..."
    sleep 2
done

echo "Postgres database is ready!"

# Wait for bucardo database to be ready
echo "Waiting for bucardo database to be ready..."
until pg_isready -h db -U postgres -d bucardo; do
    echo "Bucardo database not ready, waiting..."
    sleep 2
done

echo "Bucardo database is ready!"

# Schema is installed during deployment, just start Bucardo
echo "Bucardo schema already installed during deployment"

# Set explicit database connection for Bucardo
echo "Setting database connection environment..."
export PGPASSWORD=bucardo
export PGHOST=db
export PGPORT=5432
export PGDATABASE=bucardo
export PGUSER=bucardo

echo "Starting Bucardo daemon..."
exec bucardo start
