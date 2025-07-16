#!/usr/bin/env python3
"""
Debug version of Music Collector - Shows detailed information
"""

import os
import sys
import argparse
from pathlib import Path

def debug_setup():
    """Debug the setup and show all relevant information"""
    print("=== MUSIC COLLECTOR DEBUG ===")
    print()
    
    # Check Python
    print(f"Python version: {sys.version}")
    print(f"Python executable: {sys.executable}")
    print()
    
    # Check current directory
    print(f"Current directory: {os.getcwd()}")
    print()
    
    # Check ffmpeg path
    ffmpeg_path = r"C:\Users\cayuse\ffmpeg-2025-07-10-git-82aeee3c19-essentials_build\bin"
    ffprobe_path = os.path.join(ffmpeg_path, "ffprobe.exe")
    
    print(f"Looking for ffprobe at: {ffprobe_path}")
    if os.path.exists(ffprobe_path):
        print("✓ ffprobe.exe found")
        # Test ffprobe
        import subprocess
        try:
            result = subprocess.run([ffprobe_path, "-version"], 
                                 capture_output=True, text=True, timeout=10)
            if result.returncode == 0:
                print("✓ ffprobe.exe is working")
                print(f"  Version: {result.stdout.split()[2]}")
            else:
                print("✗ ffprobe.exe failed to run")
        except Exception as e:
            print(f"✗ Error testing ffprobe: {e}")
    else:
        print("✗ ffprobe.exe not found")
        print("  Please check your ffmpeg installation")
    print()
    
    # Check arguments
    print("Command line arguments:")
    for i, arg in enumerate(sys.argv):
        print(f"  {i}: {arg}")
    print()

def main():
    parser = argparse.ArgumentParser(description="Debug Music Collector")
    parser.add_argument("--source", help="Source directory")
    parser.add_argument("--dest", help="Destination directory")
    parser.add_argument("--genre", help="Target genre")
    parser.add_argument("--size", help="Target size")
    parser.add_argument("--debug", action="store_true", help="Show debug info")
    
    args = parser.parse_args()
    
    if args.debug or len(sys.argv) == 1:
        debug_setup()
        return
    
    # Show what we're trying to do
    print("=== MUSIC COLLECTOR DEBUG RUN ===")
    print(f"Source: {args.source}")
    print(f"Destination: {args.dest}")
    print(f"Genre: {args.genre}")
    print(f"Size: {args.size}")
    print()
    
    # Check source directory
    if args.source:
        source_path = Path(args.source)
        print(f"Checking source directory: {source_path}")
        if source_path.exists():
            print("✓ Source directory exists")
            # Count MP3 files
            mp3_count = 0
            for root, dirs, files in os.walk(source_path):
                for file in files:
                    if file.lower().endswith('.mp3'):
                        mp3_count += 1
                        if mp3_count <= 5:  # Show first 5 files
                            print(f"  Found: {os.path.join(root, file)}")
            print(f"  Total MP3 files found: {mp3_count}")
        else:
            print("✗ Source directory does not exist")
    print()
    
    # Check destination directory
    if args.dest:
        dest_path = Path(args.dest)
        print(f"Checking destination directory: {dest_path}")
        if dest_path.exists():
            print("✓ Destination directory exists")
        else:
            print("  Destination directory does not exist (will be created)")
    print()
    
    print("=== END DEBUG ===")

if __name__ == "__main__":
    main() 