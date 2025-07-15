#!/usr/bin/env python3
"""
Test script for bulk upload functionality
"""
import os
import tempfile
import subprocess
import sys

def create_test_files():
    """Create test audio files with metadata in filenames."""
    test_files = [
        "Artist Name - Album Title - 01 - Song Title.mp3",
        "Another Artist - Another Album - Song.mp3", 
        "Simple Artist - Simple Song.mp3",
        "Just A Song.mp3"
    ]
    
    temp_dir = tempfile.mkdtemp()
    created_files = []
    
    for filename in test_files:
        filepath = os.path.join(temp_dir, filename)
        with open(filepath, 'w') as f:
            f.write("fake audio content")
        created_files.append(filepath)
    
    return temp_dir, created_files

def test_bulk_upload():
    """Test the bulk upload script with various options."""
    print("Testing bulk upload functionality...")
    
    # Create test files
    temp_dir, test_files = create_test_files()
    print(f"Created {len(test_files)} test files in {temp_dir}")
    
    try:
        # Test 1: Dry run with metadata extraction
        print("\n=== Test 1: Dry run with metadata extraction ===")
        cmd = [
            sys.executable, "bulk_upload.py", 
            temp_dir, 
            "--url", "http://localhost:3000",
            "--username", "admin@musicarchive.com",
            "--password", "admin123",
            "--dry-run",
            "--verbose"
        ]
        
        result = subprocess.run(cmd, capture_output=True, text=True)
        print("STDOUT:", result.stdout)
        if result.stderr:
            print("STDERR:", result.stderr)
        
        # Test 2: Dry run with skip metadata
        print("\n=== Test 2: Dry run with skip metadata ===")
        cmd = [
            sys.executable, "bulk_upload.py", 
            temp_dir, 
            "--url", "http://localhost:3000",
            "--username", "admin@musicarchive.com",
            "--password", "admin123",
            "--dry-run",
            "--verbose",
            "--skip-metadata"
        ]
        
        result = subprocess.run(cmd, capture_output=True, text=True)
        print("STDOUT:", result.stdout)
        if result.stderr:
            print("STDERR:", result.stderr)
            
    finally:
        # Clean up
        for filepath in test_files:
            if os.path.exists(filepath):
                os.remove(filepath)
        if os.path.exists(temp_dir):
            os.rmdir(temp_dir)
        print(f"\nCleaned up test files")

if __name__ == "__main__":
    test_bulk_upload() 