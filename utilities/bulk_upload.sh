#!/bin/bash

# Music Archive Bulk Upload Script
# Usage: ./bulk_upload.sh <directory_path> [api_key]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
API_BASE_URL="http://localhost:3000/api/v1"
SUPPORTED_EXTENSIONS=("mp3" "wav" "flac" "m4a" "ogg" "aac")

# Default values
API_KEY=""
UPLOAD_DIR=""
VERBOSE=false
DRY_RUN=false

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}[$(date '+%H:%M:%S')] ${message}${NC}"
}

# Function to show usage
show_usage() {
    echo "Music Archive Bulk Upload Script"
    echo ""
    echo "Usage: $0 <directory_path> [options]"
    echo ""
    echo "Arguments:"
    echo "  directory_path    Path to directory containing audio files"
    echo ""
    echo "Options:"
    echo "  -k, --api-key KEY    API key for authentication"
    echo "  -v, --verbose         Verbose output"
    echo "  -d, --dry-run         Show what would be uploaded without actually uploading"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 /path/to/music"
    echo "  $0 /path/to/music -k your_api_key"
    echo "  $0 /path/to/music --verbose --dry-run"
}

# Function to check if file is audio
is_audio_file() {
    local file="$1"
    local ext="${file##*.}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    
    for supported in "${SUPPORTED_EXTENSIONS[@]}"; do
        if [[ "$ext" == "$supported" ]]; then
            return 0
        fi
    done
    return 1
}

# Function to get file size in human readable format
format_file_size() {
    local bytes=$1
    if [[ $bytes -gt 1073741824 ]]; then
        echo "$(echo "scale=2; $bytes/1073741824" | bc) GB"
    elif [[ $bytes -gt 1048576 ]]; then
        echo "$(echo "scale=2; $bytes/1048576" | bc) MB"
    elif [[ $bytes -gt 1024 ]]; then
        echo "$(echo "scale=2; $bytes/1024" | bc) KB"
    else
        echo "${bytes} B"
    fi
}

# Function to upload a single file
upload_file() {
    local file_path="$1"
    local file_name=$(basename "$file_path")
    local file_size=$(stat -c%s "$file_path" 2>/dev/null || stat -f%z "$file_path" 2>/dev/null)
    local file_size_formatted=$(format_file_size $file_size)
    
    print_status $BLUE "Uploading: $file_name ($file_size_formatted)"
    
    if [[ "$DRY_RUN" == true ]]; then
        print_status $YELLOW "  [DRY RUN] Would upload: $file_path"
        return 0
    fi
    
    # Upload the file using curl
    local response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: multipart/form-data" \
        -F "audio_file=@\"$file_path\"" \
        "$API_BASE_URL/songs/bulk_upload" 2>/dev/null)
    
    local http_code=$(echo "$response" | tail -n1)
    local response_body=$(echo "$response" | head -n -1)
    
    if [[ "$http_code" == "201" ]]; then
        print_status $GREEN "  ✓ Successfully uploaded: $file_name"
        if [[ "$VERBOSE" == true ]]; then
            echo "    Response: $response_body"
        fi
        return 0
    else
        print_status $RED "  ✗ Failed to upload: $file_name (HTTP $http_code)"
        if [[ "$VERBOSE" == true ]]; then
            echo "    Error: $response_body"
        fi
        return 1
    fi
}

# Function to find and upload audio files recursively
process_directory() {
    local dir="$1"
    local total_files=0
    local successful_uploads=0
    local failed_uploads=0
    
    print_status $BLUE "Scanning directory: $dir"
    
    # Find all files recursively
    while IFS= read -r -d '' file; do
        if is_audio_file "$file"; then
            ((total_files++))
            if upload_file "$file"; then
                ((successful_uploads++))
            else
                ((failed_uploads++))
            fi
        fi
    done < <(find "$dir" -type f -print0 2>/dev/null)
    
    # Print summary
    echo ""
    print_status $BLUE "Upload Summary:"
    print_status $GREEN "  Total audio files found: $total_files"
    print_status $GREEN "  Successfully uploaded: $successful_uploads"
    if [[ $failed_uploads -gt 0 ]]; then
        print_status $RED "  Failed uploads: $failed_uploads"
    fi
}

# Function to validate API key
validate_api_key() {
    if [[ -z "$API_KEY" ]]; then
        print_status $RED "Error: API key is required"
        echo "Please provide an API key using -k or --api-key option"
        exit 1
    fi
    
    # Test API key by making a simple request
    local response=$(curl -s -w "\n%{http_code}" \
        -H "Authorization: Bearer $API_KEY" \
        "$API_BASE_URL/auth/verify" 2>/dev/null)
    
    local http_code=$(echo "$response" | tail -n1)
    
    if [[ "$http_code" != "200" ]]; then
        print_status $RED "Error: Invalid API key"
        exit 1
    fi
    
    print_status $GREEN "API key validated successfully"
}

# Function to check dependencies
check_dependencies() {
    local missing_deps=()
    
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi
    
    if ! command -v find &> /dev/null; then
        missing_deps+=("find")
    fi
    
    if ! command -v stat &> /dev/null; then
        missing_deps+=("stat")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_status $RED "Error: Missing required dependencies:"
        for dep in "${missing_deps[@]}"; do
            echo "  - $dep"
        done
        exit 1
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -k|--api-key)
            API_KEY="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        -*)
            print_status $RED "Error: Unknown option $1"
            show_usage
            exit 1
            ;;
        *)
            if [[ -z "$UPLOAD_DIR" ]]; then
                UPLOAD_DIR="$1"
            else
                print_status $RED "Error: Multiple directories specified"
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate arguments
if [[ -z "$UPLOAD_DIR" ]]; then
    print_status $RED "Error: Directory path is required"
    show_usage
    exit 1
fi

if [[ ! -d "$UPLOAD_DIR" ]]; then
    print_status $RED "Error: Directory does not exist: $UPLOAD_DIR"
    exit 1
fi

# Check dependencies
check_dependencies

# Validate API key (unless dry run)
if [[ "$DRY_RUN" != true ]]; then
    validate_api_key
fi

# Start upload process
print_status $BLUE "Starting bulk upload process..."
print_status $BLUE "Directory: $UPLOAD_DIR"
if [[ "$DRY_RUN" == true ]]; then
    print_status $YELLOW "DRY RUN MODE - No files will be uploaded"
fi
if [[ "$VERBOSE" == true ]]; then
    print_status $BLUE "Verbose mode enabled"
fi
echo ""

# Process the directory
process_directory "$UPLOAD_DIR"

print_status $GREEN "Bulk upload process completed!" 