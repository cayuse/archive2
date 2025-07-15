#!/usr/bin/env python3
"""
Music Archive Bulk Upload Script (Python 3)

Usage:
    python3 bulk_upload.py <directory_path> [--username USERNAME] [--password PASSWORD] [--dry-run] [--verbose]

Arguments:
    directory_path         Path to directory containing audio files

Options:
    --username USERNAME    Username/email for authentication
    --password PASSWORD    Password for authentication
    -d, --dry-run          Show what would be uploaded without actually uploading
    -v, --verbose          Verbose output
    -h, --help             Show this help message

Example:
    python3 bulk_upload.py ~/Music --username admin@example.com --password mypass --verbose

Dependencies:
    pip install requests tqdm
"""
import os
import sys
import argparse
import mimetypes
import getpass
import requests
from tqdm import tqdm

API_BASE_URL = "http://localhost:3000/api/v1"
SUPPORTED_EXTENSIONS = {".mp3", ".wav", ".flac", ".m4a", ".ogg", ".aac"}


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


def authenticate(username, password):
    """Authenticate with the API and return the API token."""
    url = f"{API_BASE_URL}/auth/login"
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


def upload_file(filepath, api_key, dry_run=False, verbose=False):
    filename = os.path.basename(filepath)
    size = os.path.getsize(filepath)
    size_str = format_size(size)
    
    if dry_run:
        print(f"[DRY RUN] Would upload: {filename} ({size_str})")
        return True
    
    url = f"{API_BASE_URL}/songs/bulk_upload"
    headers = {"Authorization": f"Bearer {api_key}"}
    mime_type, _ = mimetypes.guess_type(filepath)
    
    try:
        with open(filepath, "rb") as f:
            files = {"audio_file": (filename, f, mime_type or "application/octet-stream")}
            response = requests.post(url, headers=headers, files=files, timeout=60)
            
            if response.status_code == 201:
                if verbose:
                    song_id = response.json().get('song', {}).get('id', 'unknown')
                    print(f"✓ Uploaded: {filename} ({size_str}) -> ID: {song_id}")
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
    parser.add_argument("--username", help="Username/email for authentication")
    parser.add_argument("--password", help="Password for authentication")
    parser.add_argument("-d", "--dry-run", action="store_true", help="Show what would be uploaded without actually uploading")
    parser.add_argument("-v", "--verbose", action="store_true", help="Verbose output")
    args = parser.parse_args()

    if not os.path.isdir(args.directory):
        print(f"Error: Directory does not exist: {args.directory}")
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
    print("Authenticating with API...")
    api_key = authenticate(username, password)
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
    
    # Upload files
    success = 0
    fail = 0
    with tqdm(audio_files, desc="Uploading", unit="file") as bar:
        for filepath in bar:
            bar.set_postfix(file=os.path.basename(filepath))
            if upload_file(filepath, api_key, dry_run=args.dry_run, verbose=args.verbose):
                success += 1
            else:
                fail += 1
    
    print(f"\nSummary: {success} succeeded, {fail} failed, {total} total.")


if __name__ == "__main__":
    main() 