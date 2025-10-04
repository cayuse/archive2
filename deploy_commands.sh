#!/bin/bash

# Archive Jukebox Deployment Commands
# This script provides common deployment and maintenance commands
# Usage: ./deploy_commands.sh [command] [options]

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}🔄${NC} $1"
}

print_success() {
    echo -e "${GREEN}✅${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠️${NC} $1"
}

print_error() {
    echo -e "${RED}❌${NC} $1"
}

# Function to check if we're in the right directory
check_directory() {
    if [ ! -f "archive/docker-compose.yml" ]; then
        print_error "docker-compose.yml not found in archive/ directory"
        print_warning "Make sure you're running this from the archive2 root directory"
        exit 1
    fi
}

# Function to check if Docker is available
check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed or not in PATH"
        exit 1
    fi
}

# Function to check if containers are running
check_containers() {
    if ! docker compose -f archive/docker-compose.yml ps | grep -q "Up"; then
        print_warning "Archive containers are not running"
        print_status "Starting containers..."
        docker compose -f archive/docker-compose.yml up -d
        sleep 5
    fi
}

# Migration command
migrate() {
    local env=${1:-production}
    print_status "Running database migrations (environment: $env)..."
    cd archive
    docker compose exec archive bin/rails db:migrate RAILS_ENV=$env
    cd ..
    print_success "Migration completed successfully!"
}

# Seed command
seed() {
    local env=${1:-production}
    print_status "Running database seed (environment: $env)..."
    cd archive
    docker compose exec archive bin/rails db:seed RAILS_ENV=$env
    cd ..
    print_success "Seed completed successfully!"
}

# Reset database command
reset_db() {
    local env=${1:-production}
    print_warning "This will DESTROY all data in the $env database!"
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" = "yes" ]; then
        print_status "Resetting database (environment: $env)..."
        cd archive
        docker compose exec archive bin/rails db:drop RAILS_ENV=$env
        docker compose exec archive bin/rails db:create RAILS_ENV=$env
        docker compose exec archive bin/rails db:migrate RAILS_ENV=$env
        cd ..
        print_success "Database reset completed!"
    else
        print_warning "Database reset cancelled"
    fi
}

# Build command
build() {
    print_status "Building Archive application..."
    cd archive
    docker compose build --no-cache
    cd ..
    print_success "Build completed!"
}

# Start command
start() {
    print_status "Starting Archive services..."
    cd archive
    docker compose up -d
    cd ..
    print_success "Services started!"
}

# Stop command
stop() {
    print_status "Stopping Archive services..."
    cd archive
    docker compose down
    cd ..
    print_success "Services stopped!"
}

# Restart command
restart() {
    print_status "Restarting Archive services..."
    cd archive
    docker compose restart
    cd ..
    print_success "Services restarted!"
}

# Logs command
logs() {
    local service=${1:-archive}
    print_status "Showing logs for service: $service"
    cd archive
    docker compose logs -f $service
}

# Status command
status() {
    print_status "Checking Archive services status..."
    cd archive
    docker compose ps
    cd ..
}

# Shell command
shell() {
    local service=${1:-archive}
    print_status "Opening shell in $service container..."
    cd archive
    docker compose exec $service /bin/bash
}

# Rails console command
console() {
    local env=${1:-production}
    print_status "Opening Rails console (environment: $env)..."
    cd archive
    docker compose exec archive bin/rails console RAILS_ENV=$env
}

# Help command
help() {
    echo "Archive Jukebox Deployment Commands"
    echo ""
    echo "Usage: $0 [command] [options]"
    echo ""
    echo "Commands:"
    echo "  migrate [env]     Run database migrations (default: production)"
    echo "  seed [env]        Run database seed (default: production)"
    echo "  reset-db [env]    Reset database (DESTROYS ALL DATA!)"
    echo "  build             Build Archive application"
    echo "  start             Start Archive services"
    echo "  stop              Stop Archive services"
    echo "  restart           Restart Archive services"
    echo "  logs [service]    Show logs for service (default: archive)"
    echo "  status            Show services status"
    echo "  shell [service]   Open shell in container (default: archive)"
    echo "  console [env]     Open Rails console (default: production)"
    echo "  help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 migrate production"
    echo "  $0 logs archive"
    echo "  $0 shell"
    echo "  $0 console production"
}

# Main script logic
main() {
    check_directory
    check_docker
    
    case "${1:-help}" in
        migrate)
            check_containers
            migrate $2
            ;;
        seed)
            check_containers
            seed $2
            ;;
        reset-db)
            check_containers
            reset_db $2
            ;;
        build)
            build
            ;;
        start)
            start
            ;;
        stop)
            stop
            ;;
        restart)
            check_containers
            restart
            ;;
        logs)
            logs $2
            ;;
        status)
            status
            ;;
        shell)
            check_containers
            shell $2
            ;;
        console)
            check_containers
            console $2
            ;;
        help|--help|-h)
            help
            ;;
        *)
            print_error "Unknown command: $1"
            echo ""
            help
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
