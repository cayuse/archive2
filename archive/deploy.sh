#!/bin/bash

# Archive Deployment Script
# This script deploys the Archive application with Docker and Apache2

set -e

echo "🎵 Archive Deployment Script"
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

# Check deployment type
if [ "$1" = "--production" ] || [ "$1" = "-p" ]; then
    export DEPLOYMENT_TYPE="production"
    print_status "Production deployment mode enabled"
elif [ "$1" = "--development" ] || [ "$1" = "-d" ]; then
    export DEPLOYMENT_TYPE="development"
    print_status "Development deployment mode enabled"
else
    export DEPLOYMENT_TYPE="development"
    print_warning "No deployment type specified, defaulting to development mode"
    print_status "Use --production or -p for production deployment on port 80"
    print_status "Use --development or -d for development deployment on port 3000"
fi

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

# Optional: Set PostgreSQL password
if [ -z "$POSTGRES_PASSWORD" ]; then
    print_warning "POSTGRES_PASSWORD not set, using default 'password'"
    export POSTGRES_PASSWORD=password
fi

# Optional: Set Archive port (default: 3000 for dev, 80 for production)
if [ -z "$ARCHIVE_PORT" ]; then
    if [ "$DEPLOYMENT_TYPE" = "production" ]; then
        export ARCHIVE_PORT=80
        print_status "Production deployment: Archive will run on port 80"
    else
        export ARCHIVE_PORT=3000
        print_warning "Development deployment: Archive will run on port 3000"
    fi
fi

# Optional: Set SMTP configuration for email delivery
if [ -z "$AWS_SES_SMTP_USERNAME" ] || [ -z "$AWS_SES_SMTP_PASSWORD" ]; then
    print_warning "AWS SES SMTP credentials not set - email functionality will be limited"
    print_status "Set AWS_SES_SMTP_USERNAME and AWS_SES_SMTP_PASSWORD for full email support"
else
    print_status "AWS SES SMTP authentication configured"
fi

# Check for AWS SES domain configuration
if [ -z "$AWS_SES_SMTP_DOMAIN" ]; then
    if [ -n "$APP_HOST" ]; then
        export AWS_SES_SMTP_DOMAIN="$APP_HOST"
        print_status "Using APP_HOST as AWS_SES_SMTP_DOMAIN: $AWS_SES_SMTP_DOMAIN"
    else
        print_warning "AWS_SES_SMTP_DOMAIN not set, using default 'cavaforge.net'"
        export AWS_SES_SMTP_DOMAIN=cavaforge.net
    fi
fi

# Required: storage path must be provided (absolute path)
if [ -z "$HOST_STORAGE_PATH" ]; then
    print_error "HOST_STORAGE_PATH not set. Please export an absolute path for storage."
    exit 1
fi
case "$HOST_STORAGE_PATH" in
    /*) : ;; # absolute
    *) print_error "HOST_STORAGE_PATH must be an absolute path (e.g., /home/shared/psql_storage)"; exit 1;;
esac
if [ ! -d "$HOST_STORAGE_PATH" ]; then
    print_status "Creating storage directory: $HOST_STORAGE_PATH"
    mkdir -p "$HOST_STORAGE_PATH"
fi

# Required: PostgreSQL data path must be provided (absolute path)
if [ -z "$POSTGRES_DATA_PATH" ]; then
    print_error "POSTGRES_DATA_PATH not set. Please export an absolute path for Postgres data."
    exit 1
fi
case "$POSTGRES_DATA_PATH" in
    /*) : ;; # absolute
    *) print_error "POSTGRES_DATA_PATH must be an absolute path (e.g., /home/shared/psql_data)"; exit 1;;
esac
if [ ! -d "$POSTGRES_DATA_PATH" ]; then
    print_status "Creating PostgreSQL data directory: $POSTGRES_DATA_PATH"
    mkdir -p "$POSTGRES_DATA_PATH"
fi

# Build and start services
print_status "Building and starting Archive services..."
docker compose up -d --build

# One-time database setup on first deploy when persistent DB is empty
print_status "Checking database initialization status..."
DB_READY=$(docker compose exec -T db bash -lc "psql -U postgres -d archive_production -Atc \"SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='schema_migrations');\"") || DB_READY="f"

if [ "${FORCE_DB_SETUP:-false}" = "true" ] || [ "$DB_READY" != "t" ]; then
  print_status "Running database setup (create/migrate${AUTO_SEED:+/seed})"
  docker compose exec -T archive bash -lc './bin/rails db:prepare'
  if [ "${AUTO_SEED:-false}" = "true" ]; then
    docker compose exec -T archive bash -lc './bin/rails db:seed || true'
  fi
else
  print_status "Database already initialized. Skipping setup. (Set FORCE_DB_SETUP=true to override)"
fi

# Wait for services to be ready
print_status "Waiting for services to be ready..."
sleep 30

# Check if archive is responding on host port
if curl -f http://localhost:${ARCHIVE_PORT}/up > /dev/null 2>&1; then
    print_success "Archive is running successfully"
else
    print_error "Archive is not responding. Check logs with: docker compose logs"
    exit 1
fi

print_success "Archive deployment completed!"
echo ""
print_status "Next steps:"
echo "1. Configure your reverse proxy (nginx/Apache) to proxy 80/443 → ${ARCHIVE_PORT}"
echo "2. Set up SSL certificates (Let's Encrypt recommended)"
echo "3. Configure your domain DNS to point to this server"
echo "4. Access your archive at: http://localhost:${ARCHIVE_PORT}"
echo "5. Default admin login: admin@cavaforge.net / admin123"
echo ""
print_warning "IMPORTANT: Change the default admin password immediately!"
echo ""
print_status "Useful commands:"
echo "- View logs: docker compose logs -f"
echo "- Stop services: docker compose down"
echo "- Update: git pull && docker compose up -d --build"
echo ""
print_status "For production deployment with nginx/SSL, see DEPLOYMENT_GUIDE.md" 