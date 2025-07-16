#!/usr/bin/env python3
"""
Music Archive Bulk Upload Script with Comprehensive Tracking (Python 3)

Usage:
    python3 bulk_upload.py <directory_path> [options]

Arguments:
    directory_path         Path to directory containing audio files

Mode Options:
    --start-over          Start fresh, ignore existing tracking data
    --resume              Resume from last successful import
    --show-errors         Show error summary and exit
    --show-errors-verbose Show detailed error information and exit

Processing Limits:
    --max-count N         Maximum number of files to process
    --continue-from N     Continue from this offset (for batch processing)

Tracking Options:
    --tracking-db PATH    SQLite database for tracking progress (default: import_tracking.db)

Authentication Options:
    --url URL             Base URL of the archive (default: http://localhost:3000)
    --username USERNAME   Username/email for authentication
    --password PASSWORD   Password for authentication

Other Options:
    -d, --dry-run         Show what would be uploaded without actually uploading
    -v, --verbose         Verbose output
    -h, --help            Show this help message

Controls:
    Press 'q'             Stop gracefully after current upload completes
    Press Ctrl+C          Stop immediately

Examples:
    # Start fresh import
    python3 bulk_upload.py ~/Music --start-over --verbose

    # Resume from where it left off
    python3 bulk_upload.py ~/Music --resume

    # Test with first 100 files
    python3 bulk_upload.py ~/Music --max-count 100

    # Continue from file 500 (for batch processing)
    python3 bulk_upload.py ~/Music --continue-from 500 --max-count 100

    # Show error summary
    python3 bulk_upload.py ~/Music --show-errors

    # Show detailed error report
    python3 bulk_upload.py ~/Music --show-errors-verbose

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
import datetime
import traceback
from tqdm import tqdm
from urllib.parse import urljoin

# Import the shared tracking module
from import_tracker import BulkImportTracker, start_job_with_defaults, resume_from_last_job

# Default API URL
DEFAULT_API_URL = "http://localhost:3000"
SUPPORTED_EXTENSIONS = {".mp3", ".wav", ".flac", ".m4a", ".ogg", ".aac"}

# Global flag for graceful shutdown
shutdown_requested = False


def is_audio_file(filepath):
    """Check if file is a supported audio file."""
    ext = os.path.splitext(filepath)[1].lower()
    return ext in SUPPORTED_EXTENSIONS


def find_audio_files(directory):
    """Find all audio files in directory recursively."""
    for root, _, files in os.walk(directory):
        for file in files:
            filepath = os.path.join(root, file)
            if is_audio_file(filepath):
                yield filepath


def format_size(bytes_size):
    """Format file size in human readable format."""
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if bytes_size < 1024.0:
            return f"{bytes_size:.2f} {unit}"
        bytes_size /= 1024.0
    return f"{bytes_size:.2f} PB"


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
    """Upload a single file to the API."""
    filename = os.path.basename(filepath)
    size = os.path.getsize(filepath)
    size_str = format_size(size)
    
    if dry_run:
        print(f"[DRY RUN] Would upload: {filename} ({size_str})")
        return True, None, "201", None
    
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
            song_id = result.get('song', {}).get('id', 'unknown')
            status = result.get('song', {}).get('processing_status', 'unknown')
            if verbose:
                print(f"✓ Uploaded: {filename} ({size_str}) -> ID: {song_id}, Status: {status}")
            return True, song_id, str(response.status_code), None
        else:
            error_msg = f"HTTP {response.status_code}: {response.text}"
            print(f"✗ Failed to upload: {filename} ({size_str}) [{error_msg}]")
            return False, None, str(response.status_code), error_msg
    except Exception as e:
        error_msg = str(e)
        print(f"✗ Exception uploading {filename}: {error_msg}")
        return False, None, "EXCEPTION", error_msg


def main():
    parser = argparse.ArgumentParser(description="Bulk upload audio files to Music Archive API with comprehensive tracking.")
    
    # Mode flags
    parser.add_argument('--start-over', action='store_true', 
                       help='Start fresh, ignore existing tracking data')
    parser.add_argument('--resume', action='store_true',
                       help='Resume from last successful import')
    parser.add_argument('--show-errors', action='store_true',
                       help='Show error summary and exit')
    parser.add_argument('--show-errors-verbose', action='store_true',
                       help='Show detailed error information and exit')
    
    # Processing limits
    parser.add_argument('--max-count', type=int,
                       help='Maximum number of files to process')
    parser.add_argument('--continue-from', type=int,
                       help='Continue from this offset (for batch processing)')
    
    # Source and tracking
    parser.add_argument("directory", help="Directory to scan for audio files")
    parser.add_argument('--tracking-db', default='import_tracking.db',
                       help='SQLite database for tracking progress')
    
    # Authentication
    parser.add_argument("--url", default=DEFAULT_API_URL, help=f"Base URL of the archive (default: {DEFAULT_API_URL})")
    parser.add_argument("--username", help="Username/email for authentication")
    parser.add_argument("--password", help="Password for authentication")
    
    # Other options
    parser.add_argument("-d", "--dry-run", action="store_true", help="Show what would be uploaded without actually uploading")
    parser.add_argument("-v", "--verbose", action="store_true", help="Verbose output")
    
    args = parser.parse_args()

    # Initialize tracker
    tracker = BulkImportTracker(args.tracking_db)
    
    # Handle reporting modes
    if args.show_errors:
        tracker.show_error_summary()
        return
    
    if args.show_errors_verbose:
        tracker.show_errors_verbose()
        return

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
    
    # Handle resume logic
    if args.start_over:
        # Clear tracking data and start fresh
        if os.path.exists(args.tracking_db):
            os.remove(args.tracking_db)
            print("🗑️  Cleared existing tracking data")
        tracker = BulkImportTracker(args.tracking_db)
    
    if args.resume:
        # Resume from last job using the shared module
        audio_files = resume_from_last_job(tracker, audio_files)
    
    # Apply limits
    if args.continue_from:
        audio_files = audio_files[args.continue_from:]
        print(f"📂 Continuing from offset {args.continue_from}: {len(audio_files)} files")
    
    if args.max_count:
        audio_files = audio_files[:args.max_count]
        print(f"📊 Limited to {args.max_count} files: {len(audio_files)} files")
    
    if len(audio_files) == 0:
        print("No files to process.")
        sys.exit(0)
    
    # Start job using the shared module
    start_job_with_defaults(tracker, len(audio_files))
    
    if args.dry_run:
        print("DRY RUN MODE - No files will be uploaded")
    
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
            
            # Record file start
            start_time = datetime.datetime.now()
            file_id = tracker.record_file_start(filepath)
            
            try:
                # Upload file
                success_flag, song_id, response_status, error_msg = upload_file(
                    filepath, 
                    args.url, 
                    api_key, 
                    dry_run=args.dry_run, 
                    verbose=args.verbose
                )
                
                processing_time = (datetime.datetime.now() - start_time).total_seconds()
                
                if success_flag:
                    tracker.record_file_success(
                        file_id, 
                        processing_time=processing_time,
                        song_id=song_id,
                        response_status=response_status,
                        upload_method="rails_api"
                    )
                    success += 1
                else:
                    tracker.record_file_failure(
                        file_id, 
                        error_msg or "Upload failed",
                        "UPLOAD_ERROR",
                        f"Response status: {response_status}",
                        upload_method="rails_api"
                    )
                    fail += 1
                    
            except Exception as e:
                processing_time = (datetime.datetime.now() - start_time).total_seconds()
                error_details = traceback.format_exc()
                tracker.record_file_failure(
                    file_id, 
                    str(e), 
                    type(e).__name__, 
                    error_details,
                    upload_method="rails_api"
                )
                fail += 1
    
    # Complete job
    tracker.complete_job()
    
    if shutdown_requested:
        print(f"\n⏹️  Upload stopped by user. Summary: {success} succeeded, {fail} failed, {len(audio_files)} total files.")
    else:
        print(f"\n✅ Upload completed. Summary: {success} succeeded, {fail} failed, {len(audio_files)} total.")


if __name__ == "__main__":
    main() 