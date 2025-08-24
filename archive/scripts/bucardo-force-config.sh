#!/bin/bash
set -e

trap 'echo "Stopping..."; su -s /bin/bash -c "HOME=/var/lib/bucardo bucardo stop" bucardo || true; exit 0' SIGTERM SIGINT

echo "Bucardo force config script starting..."

# Ensure expected home, runtime, and log directories exist
mkdir -p /var/lib/bucardo /var/run/bucardo /var/log/bucardo

# Set HOME for Bucardo user
export HOME=/var/lib/bucardo

# Defaults for connection if not provided by env
: "${PGHOST:=db}"; export PGHOST
: "${PGPORT:=5432}"; export PGPORT
: "${PGDATABASE:=bucardo}"; export PGDATABASE
: "${PGUSER:=bucardo}"; export PGUSER
: "${PGPASSWORD:=bucardo}"; export PGPASSWORD

echo "HOME set to $HOME"
echo "Database connection environment: host=$PGHOST port=$PGPORT db=$PGDATABASE user=$PGUSER"

# Ensure ownership so we can write config and logs
chown -R bucardo:bucardo /var/lib/bucardo /var/run/bucardo /var/log/bucardo || true

# Write minimal ~/.bucardorc
cat > /var/lib/bucardo/.bucardorc << EOF
# Minimal Bucardo rc
dbhost=$PGHOST
dbport=$PGPORT
dbname=$PGDATABASE
dbuser=$PGUSER
dbpass=$PGPASSWORD
EOF
chmod 600 /var/lib/bucardo/.bucardorc
chown bucardo:bucardo /var/lib/bucardo/.bucardorc

echo "Wrote /var/lib/bucardo/.bucardorc:" 
cat /var/lib/bucardo/.bucardorc

# Test database readiness explicitly
echo "Testing database readiness..."
until pg_isready -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" >/dev/null 2>&1; do
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
