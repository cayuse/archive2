#!/bin/bash

echo "=== Rails Development Environment Status Check ==="
echo

# Check if we're in the right directory
if [ ! -f "Gemfile" ]; then
    echo "❌ Not in Rails application directory"
    exit 1
fi
echo "✅ In Rails application directory"

# Check Ruby version
echo "📦 Ruby version: $(ruby --version)"

# Check if gems are installed
if bundle check >/dev/null 2>&1; then
    echo "✅ Gems are installed"
else
    echo "❌ Gems need to be installed (run: bundle install)"
fi

# Check database connection
if bin/rails db:version >/dev/null 2>&1; then
    echo "✅ Database connection working"
    echo "📊 Database version: $(bin/rails db:version)"
else
    echo "❌ Database connection failed"
fi

# Check if PostgreSQL is accessible
if command -v pg_isready >/dev/null 2>&1; then
    if pg_isready -h db -p 5432 >/dev/null 2>&1; then
        echo "✅ PostgreSQL is running"
    else
        echo "❌ PostgreSQL is not accessible"
    fi
else
    echo "⚠️  pg_isready not available, but database connection works"
fi

# Check if server can start
if bin/rails server -p 3000 -d --pid tmp/pids/server.pid >/dev/null 2>&1; then
    echo "✅ Rails server can start"
    # Kill the test server
    kill $(cat tmp/pids/server.pid) 2>/dev/null || true
    rm -f tmp/pids/server.pid
else
    echo "❌ Rails server failed to start"
fi

echo
echo "=== Environment Variables ==="
echo "POSTGRES_HOST: $POSTGRES_HOST"
echo "POSTGRES_PORT: $POSTGRES_PORT"
echo "POSTGRES_USER: $POSTGRES_USER"

echo
echo "=== Next Steps ==="
echo "If everything shows ✅, you're ready to develop!"
echo "If you see ❌, follow the steps in SETUP_STEPS.md" 