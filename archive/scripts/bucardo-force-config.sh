#!/bin/bash
set -e

trap 'echo "Stopping..."; su -s /bin/bash -c "HOME=/var/lib/bucardo bucardo stop" bucardo || true; exit 0' SIGTERM SIGINT

echo "Bucardo force config script starting..."

# Ensure expected home, runtime, and log directories exist
mkdir -p /var/lib/bucardo /var/run/bucardo /var/log/bucardo

# Set HOME for Bucardo user
export HOME=/var/lib/bucardo

# Use the Bucardo-specific environment variables
: "${BUCARDO_LOCAL_DB_HOST:=db}"; export BUCARDO_LOCAL_DB_HOST
: "${BUCARDO_LOCAL_DB_PORT:=5432}"; export BUCARDO_LOCAL_DB_PORT
: "${BUCARDO_LOCAL_DB_NAME:=bucardo}"; export BUCARDO_LOCAL_DB_NAME
: "${BUCARDO_LOCAL_DB_USER:=bucardo}"; export BUCARDO_LOCAL_DB_USER
: "${BUCARDO_LOCAL_DB_PASS:=bucardo}"; export BUCARDO_LOCAL_DB_PASS

# Also set standard PG variables for compatibility
export PGHOST=$BUCARDO_LOCAL_DB_HOST
export PGPORT=$BUCARDO_LOCAL_DB_PORT
export PGDATABASE=$BUCARDO_LOCAL_DB_NAME
export PGUSER=$BUCARDO_LOCAL_DB_USER
export PGPASSWORD=$BUCARDO_LOCAL_DB_PASS

echo "HOME set to $HOME"
echo "Database connection environment: host=$PGHOST port=$PGPORT db=$PGDATABASE user=$PGUSER"

# Ensure ownership so we can write config and logs
chown -R bucardo:bucardo /var/lib/bucardo /var/run/bucardo /var/log/bucardo || true

# Write minimal ~/.bucardorc with explicit values
cat > /var/lib/bucardo/.bucardorc << EOF
# Minimal Bucardo rc
dbhost=$BUCARDO_LOCAL_DB_HOST
dbport=$BUCARDO_LOCAL_DB_PORT
dbname=$BUCARDO_LOCAL_DB_NAME
dbuser=$BUCARDO_LOCAL_DB_USER
dbpass=$BUCARDO_LOCAL_DB_PASS
EOF
chmod 600 /var/lib/bucardo/.bucardorc
chown bucardo:bucardo /var/lib/bucardo/.bucardorc

echo "Wrote /var/lib/bucardo/.bucardorc:" 
cat /var/lib/bucardo/.bucardorc

# Test database readiness explicitly
echo "Testing database readiness..."
until pg_isready -h "$BUCARDO_LOCAL_DB_HOST" -p "$BUCARDO_LOCAL_DB_PORT" -U "$BUCARDO_LOCAL_DB_USER" -d "$BUCARDO_LOCAL_DB_NAME" >/dev/null 2>&1; do
  echo "  Database not ready, waiting..."
  sleep 2
done

# Ensure log file exists and is writable by bucardo
touch /var/log/bucardo/bucardo.log
chown bucardo:bucardo /var/log/bucardo/bucardo.log

# Start Bucardo daemon as bucardo, then tail logs to stay in foreground
echo "Starting Bucardo daemon as 'bucardo'..."
su -s /bin/bash -c "HOME=/var/lib/bucardo bucardo start || true" bucardo

echo "Tailing Bucardo log..."
exec tail -F /var/log/bucardo/bucardo.log
