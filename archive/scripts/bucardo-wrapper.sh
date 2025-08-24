#!/bin/bash
set -e

echo "Bucardo wrapper starting..."

# Force database connection environment variables
export PGPASSWORD=bucardo
export PGHOST=db
export PGPORT=5432
export PGDATABASE=bucardo
export PGUSER=bucardo

echo "Database connection environment set:"
echo "  PGHOST=$PGHOST"
echo "  PGPORT=$PGPORT"
echo "  PGDATABASE=$PGDATABASE"
echo "  PGUSER=$PGUSER"

# Test database connection
echo "Testing database connection..."
if pg_isready -h db -U bucardo -d bucardo; then
    echo "Database connection successful!"
else
    echo "Database connection failed!"
    exit 1
fi

# Start Bucardo with explicit connection parameters
echo "Starting Bucardo with explicit connection parameters..."
exec bucardo start --dbhost=db --dbport=5432 --dbname=bucardo --dbuser=bucardo --dbpass=bucardo
