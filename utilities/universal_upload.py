#!/usr/bin/env python3
"""
Music Archive Universal Upload Script with Comprehensive Tracking (Python 3)

This script is designed to be completely resilient against path and environment issues.
It works across Linux, Mac, Windows and handles any Unicode characters, spaces, 
special characters, and edge cases that could crop up.

Features:
- Cross-platform compatibility (Linux, Mac, Windows)
- Full Unicode support for filenames and paths
- Handles spaces, special characters, and any valid filesystem characters
- Resilient path handling and normalization
- Graceful error handling for all edge cases
- Concurrent uploads with configurable limits
- Comprehensive logging and debugging
- SQLite tracking database for resume capability
- Detailed error reporting and recovery

Usage:
    python3 universal_upload.py <directory_path> [options]

Arguments:
    directory_path         Path to directory containing audio files (any format supported)

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
    --concurrent CONCURRENT Number of concurrent uploads (default: 5)
    --limit LIMIT         Limit upload to first N files (useful for testing)
    -h, --help            Show this help message

Controls:
    Press 'q'             Stop gracefully after current upload completes
    Press Ctrl+C          Stop immediately

Examples:
    # Start fresh import
    python3 universal_upload.py ~/Music --start-over --verbose

    # Resume from where it left off
    python3 universal_upload.py ~/Music --resume

    # Test with first 100 files
    python3 universal_upload.py ~/Music --max-count 100

    # Continue from file 500 (for batch processing)
    python3 universal_upload.py ~/Music --continue-from 500 --max-count 100

    # Show error summary
    python3 universal_upload.py ~/Music --show-errors

    # Show detailed error report
    python3 universal_upload.py ~/Music --show-errors-verbose

    # Note: If your password contains special characters (like dashes), use single quotes:
    # python3 universal_upload.py ~/Music --username user@example.com --password '--ComplexPassword123'
    
    # Alternative: Omit --password to enter password interactively (recommended for complex passwords):
    # python3 universal_upload.py ~/Music --username user@example.com
"""

import os
import sys
import argparse
import asyncio
import aiohttp
import requests
import getpass
import signal
import threading
import time
import mimetypes
import unicodedata
import platform
import locale
import datetime
import json
import traceback
import subprocess
from urllib.parse import urljoin, quote
from pathlib import Path, PurePath
import logging

# Import the shared tracking module
from import_tracker import BulkImportTracker, start_job_with_defaults, resume_from_last_job

# Global flag for graceful shutdown
shutdown_requested = False

# Default API URL
DEFAULT_API_URL = "http://localhost:3000"

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler('upload.log', encoding='utf-8')
    ]
)
logger = logging.getLogger(__name__)

def get_system_info():
    """Get comprehensive system information for debugging."""
    info = {
        'platform': platform.platform(),
        'system': platform.system(),
        'release': platform.release(),
        'version': platform.version(),
        'machine': platform.machine(),
        'processor': platform.processor(),
        'python_version': sys.version,
        'python_implementation': platform.python_implementation(),
        'default_encoding': sys.getdefaultencoding(),
        'filesystem_encoding': sys.getfilesystemencoding(),
        'locale': locale.getlocale(),
        'cwd': os.getcwd(),
    }
    return info

def normalize_path(path):
    """
    Normalize path for cross-platform compatibility.
    Handles Unicode, spaces, special characters, and different path separators.
    """
    try:
        # Convert to Path object for cross-platform handling
        path_obj = Path(path)
        
        # Resolve any symlinks and normalize
        if path_obj.exists():
            path_obj = path_obj.resolve()
        
        # Normalize Unicode characters
        normalized = unicodedata.normalize('NFC', str(path_obj))
        
        # Handle Windows paths in different environments
        if platform.system() == "Windows":
            # Ensure proper Windows path format
            normalized = str(Path(normalized))
        else:
            # Unix-like systems
            normalized = str(Path(normalized))
        
        logger.debug(f"Path normalization: '{path}' -> '{normalized}'")
        return normalized
        
    except Exception as e:
        logger.error(f"Error normalizing path '{path}': {e}")
        # Return original path if normalization fails
        return str(path)

def is_audio_file(filepath):
    """Check if file is an audio file."""
    try:
        # Get extension in a case-insensitive way
        suffix = Path(filepath).suffix.lower()
        
        # Comprehensive list of audio file extensions
        audio_extensions = {
            '.mp3', '.m4a', '.mp4', '.ogg', '.flac', '.wav', '.aac', 
            '.wma', '.aiff', '.alac', '.m4b', '.m4p', '.3gp', '.amr',
            '.opus', '.webm', '.ra', '.rm', '.asf', '.wmv'
        }
        return suffix in audio_extensions
        
    except Exception as e:
        logger.error(f"Error checking if file is audio: {filepath}, error: {e}")
        return False

def find_audio_files(directory, limit=None):
    """Find all audio files in directory recursively with robust error handling."""
    try:
        logger.info(f"Scanning directory: {directory}")
        
        # Remove trailing slash for consistency
        clean_directory = directory.rstrip('/')
        
        # Use platform-appropriate file scanning
        if platform.system() == "Windows":
            logger.info(f"Using os.walk for Windows/WSL: {clean_directory}")
            return _find_audio_files_windows(clean_directory, limit)
        else:
            logger.info(f"Using find command for Unix: {clean_directory}")
            return _find_audio_files_unix(clean_directory, limit)
         
    except Exception as e:
        logger.error(f"Error scanning directory {directory}: {e}")
        return

def _find_audio_files_windows(directory, limit=None):
    """Find audio files using os.walk (Windows/WSL compatible)."""
    try:
        count = 0
        for root, dirs, files in os.walk(directory):
            for file in files:
                filepath = os.path.join(root, file)
                if is_audio_file(filepath):
                    logger.debug(f"Found audio file: {filepath}")
                    yield filepath
                    count += 1
                    
                    if limit and count >= limit:
                        logger.info(f"Reached limit of {limit} files, stopping scan")
                        return
        
        logger.info(f"Windows scan complete: {count} audio files found")
        
    except Exception as e:
        logger.error(f"Windows file scan failed: {e}")
        return

def _find_audio_files_unix(directory, limit=None):
    """Find audio files using find command (Unix systems)."""
    try:
        # Build find command to locate audio files with better error handling
        find_cmd = [
            'find', directory, 
            '-type', 'f',
            '(', '-iname', '*.mp3',
            '-o', '-iname', '*.m4a', 
            '-o', '-iname', '*.flac',
            '-o', '-iname', '*.wav',
            '-o', '-iname', '*.ogg', ')',
            '-print0'  # Use null-terminated output to handle special characters
        ]
        
        logger.info(f"Running command: {' '.join(find_cmd)}")
        
        # Run find command with binary output to handle null bytes
        result = subprocess.run(
            find_cmd,
            capture_output=True,
            text=False,  # Use binary mode
            timeout=300  # 5 minute timeout
        )
        
        if result.returncode != 0:
            logger.error(f"Find command failed: {result.stderr.decode('utf-8', errors='replace')}")
            return
        
        # Process null-terminated output
        output = result.stdout.decode('utf-8', errors='replace')
        files = output.split('\0')
        
        logger.info(f"Find command found {len(files)} potential audio files")
        
        count = 0
        for filepath in files:
            if not filepath.strip():
                continue
                
            logger.debug(f"Checking file: {filepath}")
            
            if is_audio_file(filepath):
                logger.debug(f"Confirmed audio file: {filepath}")
                yield filepath
                count += 1
                
                # Stop if we've reached the limit
                if limit and count >= limit:
                    logger.info(f"Reached limit of {limit} files, stopping scan")
                    return
        
        logger.info(f"Unix scan complete: {len(files)} total files, {count} audio files found")
        
    except subprocess.TimeoutExpired:
        logger.error("Find command timed out")
        return
    except Exception as e:
        logger.error(f"Find command failed: {e}")
        return

def format_size(bytes_size):
    """Format file size in human readable format."""
    try:
        for unit in ['B', 'KB', 'MB', 'GB']:
            if bytes_size < 1024.0:
                return f"{bytes_size:.1f} {unit}"
            bytes_size /= 1024.0
        return f"{bytes_size:.1f} TB"
    except Exception as e:
        logger.error(f"Error formatting size {bytes_size}: {e}")
        return "Unknown size"

def normalize_filename(filename):
    """
    Normalize filename for safe upload.
    Handles Unicode, spaces, and special characters.
    """
    try:
        # Normalize Unicode characters
        normalized = unicodedata.normalize('NFC', filename)
        
        # Replace problematic characters with safe alternatives
        # Keep original characters but ensure they're properly encoded
        safe_filename = normalized
        
        logger.debug(f"Filename normalization: '{filename}' -> '{safe_filename}'")
        return safe_filename
        
    except Exception as e:
        logger.error(f"Error normalizing filename '{filename}': {e}")
        return filename

def extract_metadata_from_filename(filename):
    """Extract metadata from filename using common patterns."""
    try:
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
        
        for pattern Counselors at Law
            import re
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
        
    except Exception as e:
        logger.error(f"Error extracting metadata from filename '{filename}': {e}")
        return {}

def clean_string(s):
    """Clean up extracted strings."""
    if not s:
        return None
    
    try:
        # Remove common separators and clean up
        cleaned = s.strip()
        cleaned = cleaned.replace('_', ' ').replace('-', ' ')  # Replace underscores and dashes with spaces
        cleaned = ' '.join(cleaned.split())  # Normalize whitespace
        cleaned = cleaned.strip()
        
        return cleaned if cleaned else None
        
    except Exception as e:
        logger.error(f"Error cleaning string '{s}': {e}")
        return None

def setup_graceful_shutdown():
    """Setup graceful shutdown handlers."""
    global shutdown_requested
    
    def signal_handler(signum, frame):
        print("\n\n⚠️  Shutdown requested. Stopping immediately...")
        global shutdown_requested
        shutdown_requested = True
        sys.exit(0)
    
    # Setup signal handlers for Ctrl+C
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    return None

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

def upload_file_universal(filepath, api_url, api_key, dry_run=False, verbose=False):
    """Upload a single file to the API with robust error handling."""
    try:
        # Normalize the filepath
        normalized_path = normalize_path(filepath)
        filename = normalize_filename(os.path.basename(normalized_path))
        size = os.path.getsize(normalized_path)
        size_str = format_size(size)
        
        if dry_run:
            print(f"[DRY RUN] Would upload: {filename} ({size_str})")
            return True, None, "201", None
        
        url = urljoin(api_url, "/api/v1/songs/bulk_upload")
        headers = {"Authorization": f"Bearer {api_key}"}
        mime_type, _ = mimetypes.guess_type(normalized_path)
        
        # Standard MIME type mapping for common audio formats
        audio_mime_types = {
            '.mp3': 'audio/mpeg',
            '.m4a': 'audio/mp4',  # Covers both AAC and ALAC
            '.ogg': 'audio/ogg',
            '.oga': 'audio/ogg',
            '.flac': 'audio/flac',
            '.wav': 'audio/wav',
            '.aac': 'audio/aac',
            '.wma': 'audio/x-ms-wma',
            '.aiff': 'audio/aiff',
            '.aif': 'audio/aiff',
            '.m4b': 'audio/mp4',
            '.m4p': 'audio/mp4',
            '.opus': 'audio/opus',
            '.amr': 'audio/amr',
            '.3gp': 'audio/3gpp',
        }
        
        # Override MIME type for audio files to ensure consistency
        suffix = Path(normalized_path).suffix.lower()
        if suffix in audio_mime_types:
            mime_type = audio_mime_types[suffix]
            if verbose:
                logger.debug(f"Overriding MIME type for {suffix}: {mime_type}")
        
        # Prepare form data
        files = {"audio_file": (filename, open(normalized_path, "rb"), mime_type or "application/octet-stream")}
        data = {"filename": filename}
        
        # Extract metadata from filename - DISABLED to let Rails extract correct metadata from audio tags
        # metadata = extract_metadata_from_filename(filename)
        # if metadata:
        #     data.update(metadata)
        
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
        print(f"✗ Exception uploading {os.path.basename(filepath)}: {error_msg}")
        return False, None, "EXCEPTION", error_msg

async def upload_files_concurrent(filepaths, api_url, api_key, max_concurrent=5, dry_run=False, verbose=False):
    """Upload multiple files concurrently with semaphore limiting."""
    semaphore = asyncio.Semaphore(max_concurrent)
    
    async def upload_with_semaphore(filepath):
        # Check for shutdown request before starting upload
        if shutdown_requested:
            return None, "shutdown_requested", None, None
        
        async with semaphore:
            try:
                # Use the synchronous upload function in a thread pool
                loop = asyncio.get_event_loop()
                result = await loop.run_in_executor(
                    None, 
                    upload_file_universal, 
                    filepath, 
                    api_url, 
                    api_key, 
                    dry_run, 
                    verbose
                )
                return filepath, *result
            except Exception as e:
                return filepath, False, "EXCEPTION", str(e)
    
    # Create tasks for all files
    tasks = [upload_with_semaphore(filepath) for filepath in filepaths]
    
    # Execute all tasks concurrently
    results = await asyncio.gather(*tasks, return_exceptions=True)
    
    return results

def main():
    parser = argparse.ArgumentParser(description="Universal upload audio files to Music Archive API with comprehensive tracking.")
    
    # Mode flags
    parser.add_argument('--start-over', action='store_true', 
                       help='Start fresh, ignore existing tracking data')
    parser.add_argument('--clear-db', action='store_true',
                       help='Clear the tracking database and start fresh (same as --start-over)')
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
    parser.add_argument('--batch-size', type=int,
                       help='Process next N unprocessed files (for repeated batch processing)')
    
    # Source and tracking
    parser.add_argument("directory", help="Directory to scan for audio files")
    parser.add_argument('--tracking-db', default='import_tracking.db',
                       help='SQLite database for tracking progress')
    
    # Authentication
    parser.add_argument("--url", default=DEFAULT_API_URL, help=f"Base URL of the archive (default: {DEFAULT_API_URL})")
    parser.add_argument("--username", help="Username/email for authentication")
    parser.add_argument("--password", nargs='?', const='', help="Password for authentication (use single quotes if password contains special characters, or omit to enter interactively)")
    
    # Other options
    parser.add_argument("-d", "--dry-run", action="store_true", help="Show what would be uploaded without actually uploading")
    parser.add_argument("-v", "--verbose", action="store_true", help="Verbose output")
    parser.add_argument("--concurrent", type=int, default=5, help="Number of concurrent uploads (default: 5)")
    parser.add_argument("--limit", type=int, help="Limit upload to first N files (useful for testing)")
    
    args = parser.parse_args()

    # Initialize tracker
    tracker = BulkImportTracker(args.tracking_db)
    
    # Handle reporting modes
    if args.show_errors:
        tracker.show_error_summary()
        return
    
    if args.show_errors_verbose:
        tracker.show_errors_verbose().

    # Handle clear-db mode (no authentication needed)
    if args.clear_db:
        if os.path.exists(args.tracking_db):
            os.remove(args.tracking_db)
            print("🗑️  Cleared tracking database")
        else:
            print("📝 No tracking database found to clear")
        return

    # Setup graceful shutdown handlers
    setup_graceful_shutdown()

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
        print("Password not provided via command line. Entering interactive mode...")
        password = getpass.getpass("Password: ").strip()
    elif password == '':
        # This happens when --password is used without a value
        print("Password argument provided but empty. Entering interactive mode...")
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

    # Find audio files - FAST MODE: scan only what we need
    if args.batch_size:
        # For batch processing, scan all files and filter for unprocessed ones
        print(f"🔍 Scanning for {args.batch_size} unprocessed files...")
        processed_files = set(tracker.get_processed_files('all'))
        
        # Get all files and filter for unprocessed ones
        all_files = list(find_audio_files(args.directory))
        unprocessed_files = [f for f in all_files if f not in processed_files]
        
        # Take the next batch_size files
        audio_files = unprocessed_files[:args.batch_size]
        
        print(f"📊 Found {len(processed_files)} already processed files")
        print(f"📊 Found {len(unprocessed_files)} unprocessed files")
        print(f"📦 Processing next batch of {len(audio_files)} files")
        
        if len(audio_files) == 0:
            print("No more unprocessed files found.")
            sys.exit(0)
    else:
        # For regular processing, use the limit if specified
        audio_files = list(find_audio_files(args.directory, args.limit))
    
    total = len(audio_files)
    if total == 0:
        print("No audio files found.")
        sys.exit(0)

    print(f"Found {total} audio files in {args.directory}")
    
    # Handle resume logic
    if args.start_over or args.clear_db:
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
    
    # Handle batch processing
    if args.batch_size:
        print(f"🎯 Processing up to {args.batch_size} new files...")
        
        # Collect files to process
        files_to_process = []
        files_checked = 0
        
        for filepath in find_audio_files(args.directory, limit=None):
            files_checked += 1
            
            # Check if file is already processed using inode tracking
            if tracker.is_file_processed(filepath):
                continue  # Skip already processed files
            
            # File is not processed, add it to our list
            files_to_process.append(filepath)
            
            # Stop when we have enough files
            if len(files_to_process) >= args.batch_size:
                break
        
        print(f"📊 Checked {files_checked} files")
        print(f"📊 Found {len(files_to_process)} new files to process")
        
        audio_files = files_to_process
    
    if len(audio_files) == 0:
        print("No files to process.")
        sys.exit(0)
    
    # Don't start a new job - use global tracking instead
    # start_job_with_defaults(tracker, len(audio_files))
    
    if args.dry_run:
        print("DRY RUN MODE - No files will be uploaded")
    
    print(f"\n💡 Press 'q' at any time to stop gracefully after current upload completes.")
    print(f"💡 Press Ctrl+C to stop immediately.\n")
    
    # Upload files
    success = 0
    fail = 0
    
    # Process files in batches for concurrent upload
    batch_size = args.concurrent
    for i in range(0, len(audio_files), batch_size):
        batch = audio_files[i:i + batch_size]
        
        # Check for shutdown request
        if shutdown_requested:
            print(f"\n🛑 Graceful shutdown requested. Stopping after current batch...")
            break
        
        print(f"Processing batch {i//batch_size + 1}/{(len(audio_files) + batch_size - 1)//batch_size} ({len(batch)} files)")
        
        # Record file starts for this batch
        file_ids = {}
        start_times = {}
        files_to_process = []
        for filepath in batch:
            # Create tracking record for this file
            file_id = tracker.record_file_start(filepath)
            file_ids[filepath] = file_id
            start_times[filepath] = datetime.datetime.now()
            files_to_process.append(filepath)
        
        if not files_to_process:
            print("All files in this batch were already processed, skipping batch")
            continue
        
        try:
            # Upload batch concurrently
            results = asyncio.run(upload_files_concurrent(
                files_to_process, 
                args.url, 
                api_key, 
                args.concurrent, 
                args.dry_run, 
                args.verbose
            ))
            
            # Process results
            for filepath, success_flag, song_id, response_status, error_msg in results:
                if filepath is None:
                    continue  # Skip shutdown requests
                
                file_id = file_ids.get(filepath)
                if file_id is None:
                    continue
                
                processing_time = (datetime.datetime.now() - start_times[filepath]).total_seconds()
                
                if success_flag:
                    tracker.record_file_success(
                        file_id, 
                        processing_time=processing_time,
                        song_id=song_id,
                        response_status=response_status,
                        upload_method="direct_fs"
                    )
                    success += 1
                else:
                    tracker.record_file_failure(
                        file_id, 
                        error_msg or "Upload failed",
                        "UPLOAD_ERROR",
                        f"Response status: {response_status}",
                        upload_method="direct_fs"
                    )
                    fail += 1
                    
        except Exception as e:
            # Handle batch-level errors
            for filepath in batch:
                file_id = file_ids.get(filepath)
                if file_id:
                    processing_time = (datetime.datetime.now() - start_times[filepath]).total_seconds()
                    error_details = traceback.format_exc()
                    tracker.record_file_failure(
                        file_id, 
                        str(e), 
                        type(e).__name__, 
                        error_details,
                        upload_method="direct_fs"
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