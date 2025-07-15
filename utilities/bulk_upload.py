#!/usr/bin/env python3
"""
Music Archive Bulk Upload Script (Python 3)

Usage:
    python3 bulk_upload.py <directory_path> [--url URL] [--username USERNAME] [--password PASSWORD] [--dry-run] [--verbose]

Arguments:
    directory_path         Path to directory containing audio files

Options:
    --url URL              Base URL of the archive (default: http://localhost:3000)
    --username USERNAME    Username/email for authentication
    --password PASSWORD    Password for authentication
    -d, --dry-run          Show what would be uploaded without actually uploading
    -v, --verbose          Verbose output
    -h, --help             Show this help message

Controls:
    Press 'q'              Stop gracefully after current upload completes
    Press Ctrl+C           Stop immediately

Example:
    python3 bulk_upload.py ~/Music --url http://myarchive.com --username admin@example.com --password mypass --verbose

Dependencies:
    pip install requests tqdm
"""
import os
import sys
import argparse
import mimetypes
import getpass
import re
import requests
import signal
import threading
import time
from tqdm import tqdm
from urllib.parse import urljoin

# Default API URL
DEFAULT_API_URL = "http://localhost:3000"
SUPPORTED_EXTENSIONS = {".mp3", ".wav", ".flac", ".m4a", ".ogg", ".aac"}

# Global flag for graceful shutdown
shutdown_requested = False


def is_audio_file(filepath):
    ext = os.path.splitext(filepath)[1].lower()
    return ext in SUPPORTED_EXTENSIONS


def find_audio_files(directory):
    for root, _, files in os.walk(directory):
        for file in files:
            filepath = os.path.join(root, file)
            if is_audio_file(filepath):
                yield filepath


def format_size(bytes_size):
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if bytes_size < 1024.0:
            return f"{bytes_size:.2f} {unit}"
        bytes_size /= 1024.0
    return f"{bytes_size:.2f} PB"


def extract_metadata_from_filename(filename):
    """Extract metadata from filename using common patterns."""
    # Remove extension
    name = os.path.splitext(filename)[0]
    
    # Common filename patterns
    patterns = [
        # Artist - Album - Track - Title
        r'^(.+?)\s*-\s*(.+?)\s*-\s*(\d+)\s*-\s*(.+)$',
        # Artist - Album - Title
        r'^(.+?)\s*-\s*(.+?)\s*-\s*(.+)$',
        # Artist - Title
        r'^(.+?)\s*-\s*(.+)$',
        # Just title
        r'^(.+)$'
    ]
    
    metadata = {}
    
    for pattern in patterns:
        match = re.match(pattern, name, re.IGNORECASE)
        if match:
            groups = match.groups()
            if len(groups) == 4:  # Artist - Album - Track - Title
                metadata['artist_name'] = clean_string(groups[0])
                metadata['album_title'] = clean_string(groups[1])
                metadata['track_number'] = int(groups[2])
                metadata['title'] = clean_string(groups[3])
            elif len(groups) == 3:  # Artist - Album - Title
                metadata['artist_name'] = clean_string(groups[0])
                metadata['album_title'] = clean_string(groups[1])
                metadata['title'] = clean_string(groups[2])
            elif len(groups) == 2:  # Artist - Title
                metadata['artist_name'] = clean_string(groups[0])
                metadata['title'] = clean_string(groups[1])
            elif len(groups) == 1:  # Just title
                metadata['title'] = clean_string(groups[0])
            break
    
    return metadata


def clean_string(s):
    """Clean up extracted strings."""
    if not s:
        return None
    
    # Remove common separators and clean up
    cleaned = s.strip()
    cleaned = re.sub(r'[_-]', ' ', cleaned)  # Replace underscores and dashes with spaces
    cleaned = re.sub(r'\s+', ' ', cleaned)   # Normalize whitespace
    cleaned = cleaned.strip()
    
    return cleaned if cleaned else None


def setup_graceful_shutdown():
    """Setup graceful shutdown handlers."""
    global shutdown_requested
    
    def signal_handler(signum, frame):
        print("\n\n⚠️  Shutdown requested. Finishing current upload and stopping gracefully...")
        global shutdown_requested
        shutdown_requested = True
    
    def keyboard_listener():
        """Listen for 'q' key press in a separate thread."""
        global shutdown_requested
        while not shutdown_requested:
            try:
                # Non-blocking input check
                if sys.platform == "win32":
                    import msvcrt
                    if msvcrt.kbhit():
                        key = msvcrt.getch().decode('utf-8').lower()
                        if key == 'q':
                            print("\n\n⚠️  'q' pressed. Finishing current upload and stopping gracefully...")
                            shutdown_requested = True
                            break
                else:
                    # Unix-like systems
                    import select
                    if select.select([sys.stdin], [], [], 0.1)[0]:
                        key = sys.stdin.read(1).lower()
                        if key == 'q':
                            print("\n\n⚠️  'q' pressed. Finishing current upload and stopping gracefully...")
                            shutdown_requested = True
                            break
            except:
                pass
            time.sleep(0.1)
    
    # Setup signal handlers for Ctrl+C
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    # Start keyboard listener thread
    keyboard_thread = threading.Thread(target=keyboard_listener, daemon=True)
    keyboard_thread.start()
    
    return keyboard_thread


def authenticate(api_url, username, password):
    """Authenticate with the API and return the API token."""
    url = urljoin(api_url, "/api/v1/auth/login")
    data = {"email": username, "password": password}
    
    try:
        response = requests.post(url, json=data, timeout=30)
        if response.status_code == 200:
            result = response.json()
            if result.get("success") and "api_token" in result:
                return result["api_token"]
            else:
                print(f"Authentication failed: {result.get('message', 'Unknown error')}")
                return None
        else:
            print(f"Authentication failed (HTTP {response.status_code}): {response.text}")
            return None
    except requests.exceptions.RequestException as e:
        print(f"Network error during authentication: {e}")
        return None


def upload_file(filepath, api_url, api_key, dry_run=False, verbose=False):
    filename = os.path.basename(filepath)
    size = os.path.getsize(filepath)
    size_str = format_size(size)
    
    if dry_run:
        print(f"[DRY RUN] Would upload: {filename} ({size_str})")
        return True
    
    url = urljoin(api_url, "/api/v1/songs/bulk_upload")
    headers = {"Authorization": f"Bearer {api_key}"}
    mime_type, _ = mimetypes.guess_type(filepath)
    
    # Prepare form data - only send filename and audio file
    files = {"audio_file": (filename, open(filepath, "rb"), mime_type or "application/octet-stream")}
    data = {"filename": filename}  # Required filename parameter
    
    try:
        response = requests.post(url, headers=headers, files=files, data=data, timeout=60)
        
        if response.status_code == 201:
            result = response.json()
            if verbose:
                song_id = result.get('song', {}).get('id', 'unknown')
                status = result.get('song', {}).get('processing_status', 'unknown')
                print(f"✓ Uploaded: {filename} ({size_str}) -> ID: {song_id}, Status: {status}")
            return True
        else:
            print(f"✗ Failed to upload: {filename} ({size_str}) [HTTP {response.status_code}] {response.text}")
            return False
    except Exception as e:
        print(f"✗ Exception uploading {filename}: {e}")
        return False


def main():
    parser = argparse.ArgumentParser(description="Bulk upload audio files to Music Archive API.")
    parser.add_argument("directory", help="Directory to scan for audio files")
    parser.add_argument("--url", default=DEFAULT_API_URL, help=f"Base URL of the archive (default: {DEFAULT_API_URL})")
    parser.add_argument("--username", help="Username/email for authentication")
    parser.add_argument("--password", help="Password for authentication")
    parser.add_argument("-d", "--dry-run", action="store_true", help="Show what would be uploaded without actually uploading")
    parser.add_argument("-v", "--verbose", action="store_true", help="Verbose output")
    args = parser.parse_args()

    # Setup graceful shutdown handlers
    keyboard_thread = setup_graceful_shutdown()

    if not os.path.isdir(args.directory):
        print(f"Error: Directory does not exist: {args.directory}")
        sys.exit(1)

    # Validate URL
    if not args.url.startswith(('http://', 'https://')):
        print(f"Error: Invalid URL format: {args.url}")
        sys.exit(1)

    # Get authentication credentials
    username = args.username
    password = args.password
    
    if not username:
        username = input("Username/Email: ").strip()
    
    if not password:
        password = getpass.getpass("Password: ").strip()
    
    if not username or not password:
        print("Error: Username and password are required")
        sys.exit(1)

    # Authenticate and get API token
    print(f"Authenticating with API at {args.url}...")
    api_key = authenticate(args.url, username, password)
    if not api_key:
        print("Authentication failed. Please check your credentials.")
        sys.exit(1)
    
    print("✓ Authentication successful!")

    # Find audio files
    audio_files = list(find_audio_files(args.directory))
    total = len(audio_files)
    if total == 0:
        print("No audio files found.")
        sys.exit(0)

    print(f"Found {total} audio files in {args.directory}")
    
    if args.dry_run:
        print("DRY RUN MODE - No files will be uploaded")
    
    # Show processing options
    if args.verbose:
        print(f"Processing options:")
        print(f"  - API URL: {args.url}")
        print(f"  - Server will handle all metadata extraction")
    
    print(f"\n💡 Press 'q' at any time to stop gracefully after current upload completes.")
    print(f"💡 Press Ctrl+C to stop immediately.\n")
    
    # Upload files
    success = 0
    fail = 0
    with tqdm(audio_files, desc="Uploading", unit="file") as bar:
        for filepath in bar:
            # Check for shutdown request
            if shutdown_requested:
                print(f"\n🛑 Graceful shutdown requested. Stopping after current upload...")
                break
                
            bar.set_postfix(file=os.path.basename(filepath))
            if upload_file(
                filepath, 
                args.url, 
                api_key, 
                dry_run=args.dry_run, 
                verbose=args.verbose
            ):
                success += 1
            else:
                fail += 1
    
    if shutdown_requested:
        print(f"\n⏹️  Upload stopped by user. Summary: {success} succeeded, {fail} failed, {len(audio_files)} total files.")
    else:
        print(f"\n✅ Upload completed. Summary: {success} succeeded, {fail} failed, {total} total.")


if __name__ == "__main__":
    main() 