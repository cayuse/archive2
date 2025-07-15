#!/bin/bash

# Test script for Music Archive API
# This script demonstrates how to authenticate and upload songs

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
API_BASE_URL="http://localhost:3000/api/v1"
TEST_EMAIL="admin@example.com"
TEST_PASSWORD="password123"

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}[$(date '+%H:%M:%S')] ${message}${NC}"
}

# Function to check if server is running
check_server() {
    print_status $BLUE "Checking if server is running..."
    
    if curl -s "http://localhost:3000" > /dev/null 2>&1; then
        print_status $GREEN "✓ Server is running"
        return 0
    else
        print_status $RED "✗ Server is not running"
        print_status $YELLOW "Please start the Rails server with: bin/rails server"
        return 1
    fi
}

# Function to authenticate and get API token
authenticate() {
    print_status $BLUE "Authenticating with API..."
    
    local response=$(curl -s -w "\n%{http_code}" \
        -X POST "$API_BASE_URL/auth/login" \
        -H "Content-Type: application/json" \
        -d "{
            \"email\": \"$TEST_EMAIL\",
            \"password\": \"$TEST_PASSWORD\"
        }" 2>/dev/null)
    
    local http_code=$(echo "$response" | tail -n1)
    local response_body=$(echo "$response" | head -n -1)
    
    if [[ "$http_code" == "200" ]]; then
        local api_token=$(echo "$response_body" | grep -o '"api_token":"[^"]*"' | cut -d'"' -f4)
        if [[ -n "$api_token" ]]; then
            print_status $GREEN "✓ Authentication successful"
            echo "$api_token"
        else
            print_status $RED "✗ No API token in response"
            echo "$response_body"
            return 1
        fi
    else
        print_status $RED "✗ Authentication failed (HTTP $http_code)"
        echo "$response_body"
        return 1
    fi
}

# Function to test API token verification
test_token_verification() {
    local api_token="$1"
    
    print_status $BLUE "Testing API token verification..."
    
    local response=$(curl -s -w "\n%{http_code}" \
        -H "Authorization: Bearer $api_token" \
        "$API_BASE_URL/auth/verify")
    
    local http_code=$(echo "$response" | tail -n1)
    local response_body=$(echo "$response" | head -n -1)
    
    if [[ "$http_code" == "200" ]]; then
        print_status $GREEN "✓ API token verification successful"
        return 0
    else
        print_status $RED "✗ API token verification failed (HTTP $http_code)"
        echo "$response_body"
        return 1
    fi
}

# Function to test songs list endpoint
test_songs_list() {
    local api_token="$1"
    
    print_status $BLUE "Testing songs list endpoint..."
    
    local response=$(curl -s -w "\n%{http_code}" \
        -H "Authorization: Bearer $api_token" \
        "$API_BASE_URL/songs?limit=5")
    
    local http_code=$(echo "$response" | tail -n1)
    local response_body=$(echo "$response" | head -n -1)
    
    if [[ "$http_code" == "200" ]]; then
        print_status $GREEN "✓ Songs list retrieved successfully"
        local song_count=$(echo "$response_body" | grep -o '"total":[0-9]*' | cut -d':' -f2)
        print_status $BLUE "  Total songs in database: $song_count"
        return 0
    else
        print_status $RED "✗ Failed to retrieve songs list (HTTP $http_code)"
        echo "$response_body"
        return 1
    fi
}

# Function to test bulk upload (dry run)
test_bulk_upload() {
    local api_token="$1"
    
    print_status $BLUE "Testing bulk upload endpoint (dry run)..."
    
    # Create a test file
    local test_file="/tmp/test_audio.mp3"
    echo "This is a test audio file" > "$test_file"
    
    local response=$(curl -s -w "\n%{http_code}" \
        -X POST "$API_BASE_URL/songs/bulk_upload" \
        -H "Authorization: Bearer $api_token" \
        -F "audio_file=@$test_file")
    
    local http_code=$(echo "$response" | tail -n1)
    local response_body=$(echo "$response" | head -n -1)
    
    # Clean up test file
    rm -f "$test_file"
    
    if [[ "$http_code" == "201" ]]; then
        print_status $GREEN "✓ Bulk upload endpoint working"
        local song_id=$(echo "$response_body" | grep -o '"id":[0-9]*' | cut -d':' -f2)
        print_status $BLUE "  Created song ID: $song_id"
        return 0
    else
        print_status $RED "✗ Bulk upload failed (HTTP $http_code)"
        echo "$response_body"
        return 1
    fi
}

# Main test function
run_tests() {
    print_status $BLUE "Starting API tests..."
    echo ""
    
    # Check if server is running
    if ! check_server; then
        exit 1
    fi
    
    # Authenticate and get API token
    local api_token=$(authenticate)
    if [[ $? -ne 0 ]] || [[ -z "$api_token" ]]; then
        print_status $RED "Authentication failed. Please check your credentials."
        exit 1
    fi
    
    echo ""
    
    # Test token verification
    if ! test_token_verification "$api_token"; then
        exit 1
    fi
    
    echo ""
    
    # Test songs list
    if ! test_songs_list "$api_token"; then
        exit 1
    fi
    
    echo ""
    
    # Test bulk upload
    if ! test_bulk_upload "$api_token"; then
        exit 1
    fi
    
    echo ""
    print_status $GREEN "All API tests completed successfully!"
    print_status $BLUE "You can now use the bulk_upload.sh script with your API token."
}

# Show usage
show_usage() {
    echo "Music Archive API Test Script"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -e, --email EMAIL     Test email (default: admin@example.com)"
    echo "  -p, --password PASS   Test password (default: password123)"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "This script tests the Music Archive API endpoints."
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--email)
            TEST_EMAIL="$2"
            shift 2
            ;;
        -p|--password)
            TEST_PASSWORD="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_status $RED "Error: Unknown option $1"
            show_usage
            exit 1
            ;;
    esac
done

# Run tests
run_tests 