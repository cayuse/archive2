#!/bin/bash

# Music Archive App - Complete Setup Script
# This script provides a repeatable setup process for both Docker and local development

set -e  # Exit on any error

echo "🎵 Music Archive App - Setup Script"
echo "=================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
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

# Check if we're in the right directory
if [ ! -f "docker-compose.yml" ]; then
    print_error "docker-compose.yml not found. Please run this script from the project root directory."
    exit 1
fi

# Function to check if Docker is available
check_docker() {
    if command -v docker &> /dev/null && command -v docker-compose &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to setup local development
setup_local() {
    print_status "Setting up local development environment..."
    
    if [ ! -d "archive" ]; then
        print_error "archive directory not found. Please ensure you're in the correct project directory."
        exit 1
    fi
    
    cd archive
    
    # Check if Ruby is available
    if ! command -v ruby &> /dev/null; then
        print_error "Ruby is not installed. Please install Ruby 3.3.8 or later."
        exit 1
    fi
    
    print_status "Ruby version: $(ruby --version)"
    
    # Remove old credentials if they exist
    if [ -f "config/credentials.yml.enc" ] || [ -f "config/master.key" ]; then
        print_warning "Removing existing credentials for clean setup..."
        rm -f config/credentials.yml.enc config/master.key
    fi
    
    # Generate new credentials
    print_status "Generating new Rails credentials..."
    if [ -z "$EDITOR" ]; then
        export EDITOR=vi
    fi
    bin/rails credentials:edit
    
    # Make scripts executable
    print_status "Setting up executable permissions..."
    chmod +x bin/*
    
    # Run the setup script
    print_status "Running development setup..."
    ./bin/setup-dev
    
    print_success "Local development setup complete!"
    print_status "You can now start the server with: bin/rails server"
}

# Function to setup Docker environment
setup_docker() {
    print_status "Setting up Docker environment..."
    
    # Check if we need to generate credentials for Docker
    if [ ! -f "archive/config/master.key" ]; then
        print_status "Generating credentials for Docker..."
        cd archive
        
        # Remove old credentials if they exist
        rm -f config/credentials.yml.enc config/master.key
        
        # Generate new credentials
        if [ -z "$EDITOR" ]; then
            export EDITOR=vi
        fi
        bin/rails credentials:edit
        
        cd ..
    fi
    
    # Build and start containers
    print_status "Building and starting Docker containers..."
    docker-compose up --build -d
    
    print_success "Docker setup complete!"
    print_status "The application should be available at: http://localhost:3000"
}

# Function to check application status
check_status() {
    print_status "Checking application status..."
    
    if [ -f "archive/check_status.sh" ]; then
        cd archive
        ./check_status.sh
        cd ..
    else
        print_warning "check_status.sh not found. Manual status check required."
        
        # Basic status checks
        if check_docker; then
            print_status "Docker containers:"
            docker-compose ps
        fi
        
        print_status "You can manually check the application at: http://localhost:3000"
    fi
}

# Main setup logic
main() {
    echo ""
    print_status "Choose your setup method:"
    echo "1) Docker (Recommended - includes database)"
    echo "2) Local development (requires Ruby, PostgreSQL)"
    echo "3) Check status only"
    echo ""
    read -p "Enter your choice (1-3): " choice
    
    case $choice in
        1)
            if check_docker; then
                setup_docker
            else
                print_error "Docker is not available. Please install Docker and Docker Compose."
                exit 1
            fi
            ;;
        2)
            setup_local
            ;;
        3)
            check_status
            ;;
        *)
            print_error "Invalid choice. Please run the script again."
            exit 1
            ;;
    esac
    
    echo ""
    print_success "Setup complete!"
    echo ""
    print_status "Next steps:"
    echo "1. Visit: http://localhost:3000"
    echo "2. Login with:"
    echo "   Email: admin@musicarchive.com"
    echo "   Password: admin123"
    echo ""
    print_status "Useful commands:"
    echo "- Check status: ./check_status.sh (from archive directory)"
    echo "- View logs: docker-compose logs (if using Docker)"
    echo "- Rails console: cd archive && bin/rails console"
    echo "- Stop server: docker-compose down (if using Docker) or Ctrl+C (if local)"
    echo ""
}

# Run main function
main 