#!/usr/bin/env python3
"""
Music Collector - Windows Script for Collecting Music by Genre

This script scans a music library, identifies music by ID3 tags, and copies
a specified amount of data to a destination folder.

Features:
- Genre-based filtering (country, rock, jazz, etc.)
- Random music selection
- Size-based collection (e.g., 1GB)
- Progress tracking
- Duplicate handling
- Detailed logging
- SQLite caching for fast subsequent runs

Usage:
    python music_collector.py --source "C:\Music" --dest "C:\Country_Collection" --genre country --size 1gb
    python music_collector.py --source "C:\Music" --dest "C:\Random_Collection" --random --size 500mb
"""

import os
import sys
import shutil
import argparse
import random
import logging
import json
import sqlite3
import hashlib
from pathlib import Path
from typing import List, Dict, Optional, Tuple
import subprocess
import re
from dataclasses import dataclass
from datetime import datetime

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('music_collector.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

@dataclass
class MusicFile:
    """Represents a music file with metadata"""
    path: Path
    size: int
    genre: Optional[str] = None
    title: Optional[str] = None
    artist: Optional[str] = None
    album: Optional[str] = None
    year: Optional[str] = None
    last_modified: Optional[float] = None

class MusicCollector:
    def __init__(self, ffmpeg_path: str = None):
        """Initialize the music collector"""
        self.ffmpeg_path = ffmpeg_path or r"C:\Users\cayuse\ffmpeg-2025-07-10-git-82aeee3c19-essentials_build\bin"
        self.ffprobe_path = os.path.join(self.ffmpeg_path, "ffprobe.exe")
        
        # Verify ffprobe is available
        if not os.path.exists(self.ffprobe_path):
            raise FileNotFoundError(f"ffprobe not found at {self.ffprobe_path}")
        
        logger.info(f"Using ffprobe at: {self.ffprobe_path}")
        
        # Initialize SQLite database
        self.db_path = "music_cache.db"
        self.init_database()
        
        # Genre mappings for better matching
        self.genre_mappings = {
            'country': ['country', 'country & western', 'country and western', 'americana'],
            'rock': ['rock', 'hard rock', 'soft rock', 'classic rock', 'alternative rock'],
            'jazz': ['jazz', 'smooth jazz', 'bebop', 'swing'],
            'blues': ['blues', 'rhythm and blues', 'r&b'],
            'pop': ['pop', 'popular'],
            'classical': ['classical', 'orchestral', 'symphony'],
            'electronic': ['electronic', 'edm', 'dance', 'techno', 'house'],
            'hip hop': ['hip hop', 'rap', 'hip-hop'],
            'folk': ['folk', 'folk rock'],
            'reggae': ['reggae', 'ska'],
            'metal': ['metal', 'heavy metal', 'death metal', 'black metal'],
            'punk': ['punk', 'punk rock'],
            'soul': ['soul', 'motown'],
            'funk': ['funk', 'funk rock'],
            'disco': ['disco'],
            'gospel': ['gospel', 'christian'],
            'world': ['world', 'world music', 'ethnic'],
            'soundtrack': ['soundtrack', 'score', 'film score'],
            'children': ['children', 'kids', 'children\'s'],
            'comedy': ['comedy', 'humor', 'humour']
        }

    def init_database(self):
        """Initialize SQLite database for caching"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Create table for music file metadata
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS music_files (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                file_path TEXT UNIQUE NOT NULL,
                file_size INTEGER NOT NULL,
                last_modified REAL NOT NULL,
                genre TEXT,
                title TEXT,
                artist TEXT,
                album TEXT,
                year TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        conn.commit()
        conn.close()
        logger.info(f"Database initialized: {self.db_path}")

    def get_file_hash(self, file_path: Path) -> str:
        """Get a hash of the file path and modification time for cache invalidation"""
        try:
            stat = file_path.stat()
            # Use path + size + modification time as hash
            hash_data = f"{file_path}_{stat.st_size}_{stat.st_mtime}"
            return hashlib.md5(hash_data.encode()).hexdigest()
        except OSError:
            return ""

    def get_cached_metadata(self, file_path: Path) -> Optional[MusicFile]:
        """Get metadata from cache if available and current"""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            cursor.execute('''
                SELECT file_size, last_modified, genre, title, artist, album, year
                FROM music_files 
                WHERE file_path = ?
            ''', (str(file_path),))
            
            result = cursor.fetchone()
            conn.close()
            
            if result:
                cached_size, cached_mtime, genre, title, artist, album, year = result
                
                # Check if file still exists and hasn't changed
                if file_path.exists():
                    current_stat = file_path.stat()
                    if (current_stat.st_size == cached_size and 
                        abs(current_stat.st_mtime - cached_mtime) < 1):  # Within 1 second
                        
                        return MusicFile(
                            path=file_path,
                            size=cached_size,
                            genre=genre,
                            title=title,
                            artist=artist,
                            album=album,
                            year=year,
                            last_modified=cached_mtime
                        )
            
            return None
            
        except Exception as e:
            logger.warning(f"Error reading cache for {file_path}: {e}")
            return None

    def cache_metadata(self, music_file: MusicFile):
        """Cache metadata in SQLite database"""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            cursor.execute('''
                INSERT OR REPLACE INTO music_files 
                (file_path, file_size, last_modified, genre, title, artist, album, year)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                str(music_file.path),
                music_file.size,
                music_file.last_modified or 0,
                music_file.genre,
                music_file.title,
                music_file.artist,
                music_file.album,
                music_file.year
            ))
            
            conn.commit()
            conn.close()
            
        except Exception as e:
            logger.warning(f"Error caching metadata for {music_file.path}: {e}")

    def parse_size(self, size_str: str) -> int:
        """Parse size string (e.g., '1gb', '500mb') to bytes"""
        size_str = size_str.lower().strip()
        
        # Extract number and unit
        match = re.match(r'(\d+(?:\.\d+)?)\s*(gb|mb|kb|b)?', size_str)
        if not match:
            raise ValueError(f"Invalid size format: {size_str}")
        
        number = float(match.group(1))
        unit = match.group(2) or 'b'
        
        multipliers = {
            'b': 1,
            'kb': 1024,
            'mb': 1024 * 1024,
            'gb': 1024 * 1024 * 1024
        }
        
        return int(number * multipliers[unit])

    def get_file_size(self, file_path: Path) -> int:
        """Get file size in bytes"""
        try:
            return file_path.stat().st_size
        except OSError as e:
            logger.warning(f"Could not get size for {file_path}: {e}")
            return 0

    def extract_metadata(self, file_path: Path) -> Optional[MusicFile]:
        """Extract metadata from music file using ffprobe"""
        try:
            # Use ffprobe to get metadata
            cmd = [
                self.ffprobe_path,
                '-v', 'quiet',
                '-print_format', 'json',
                '-show_format',
                str(file_path)
            ]
            
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            
            if result.returncode != 0:
                logger.warning(f"ffprobe failed for {file_path}: {result.stderr}")
                return None
            
            data = json.loads(result.stdout)
            format_info = data.get('format', {})
            tags = format_info.get('tags', {})
            
            # Extract metadata
            genre = tags.get('genre', '').lower().strip()
            title = tags.get('title', '').strip()
            artist = tags.get('artist', '').strip()
            album = tags.get('album', '').strip()
            year = tags.get('date', '').strip()
            
            # Clean up genre
            if genre:
                # Remove common prefixes/suffixes
                genre = re.sub(r'^genre\s*:', '', genre, flags=re.IGNORECASE)
                genre = genre.strip()
            
            stat = file_path.stat()
            return MusicFile(
                path=file_path,
                size=self.get_file_size(file_path),
                genre=genre,
                title=title,
                artist=artist,
                album=album,
                year=year,
                last_modified=stat.st_mtime
            )
            
        except subprocess.TimeoutExpired:
            logger.warning(f"Timeout extracting metadata from {file_path}")
            return None
        except json.JSONDecodeError:
            logger.warning(f"Invalid JSON from ffprobe for {file_path}")
            return None
        except Exception as e:
            logger.warning(f"Error extracting metadata from {file_path}: {e}")
            return None

    def scan_directory(self, source_dir: Path, max_files: int = None, force_rescan: bool = False, cache_only: bool = False) -> List[MusicFile]:
        """Scan directory for MP3 files and extract metadata"""
        music_files = []
        processed = 0
        cached_count = 0
        new_count = 0
        
        if cache_only:
            logger.info("Cache-only mode: Using only cached metadata")
            return self.get_all_cached_files(max_files)
        
        logger.info(f"Scanning directory: {source_dir}")
        if not force_rescan:
            logger.info("Using cached metadata when available (use --force-rescan to bypass cache)")
        
        # Walk through directory recursively
        for root, dirs, files in os.walk(source_dir):
            root_path = Path(root)
            
            for file in files:
                if file.lower().endswith('.mp3'):
                    file_path = root_path / file
                    
                    # Check cache first (unless force rescan)
                    if not force_rescan:
                        cached_file = self.get_cached_metadata(file_path)
                        if cached_file:
                            music_files.append(cached_file)
                            cached_count += 1
                            processed += 1
                            
                            if processed % 100 == 0:
                                logger.info(f"Processed {processed} files (cached: {cached_count}, new: {new_count})...")
                            
                            if max_files and processed >= max_files:
                                logger.info(f"Reached max files limit: {max_files}")
                                break
                            continue
                    
                    # Extract metadata for new/updated files
                    music_file = self.extract_metadata(file_path)
                    if music_file:
                        music_files.append(music_file)
                        new_count += 1
                        processed += 1
                        
                        # Cache the metadata
                        self.cache_metadata(music_file)
                        
                        if processed % 100 == 0:
                            logger.info(f"Processed {processed} files (cached: {cached_count}, new: {new_count})...")
                        
                        if max_files and processed >= max_files:
                            logger.info(f"Reached max files limit: {max_files}")
                            break
            
            if max_files and processed >= max_files:
                break
        
        logger.info(f"Found {len(music_files)} MP3 files (cached: {cached_count}, new: {new_count})")
        return music_files

    def get_all_cached_files(self, max_files: int = None) -> List[MusicFile]:
        """Get all cached files from database"""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            query = '''
                SELECT file_path, file_size, last_modified, genre, title, artist, album, year
                FROM music_files
                ORDER BY file_path
            '''
            
            if max_files:
                query += f' LIMIT {max_files}'
            
            cursor.execute(query)
            results = cursor.fetchall()
            conn.close()
            
            music_files = []
            for result in results:
                file_path, file_size, last_modified, genre, title, artist, album, year = result
                path = Path(file_path)
                
                # Only include if file still exists
                if path.exists():
                    music_files.append(MusicFile(
                        path=path,
                        size=file_size,
                        genre=genre,
                        title=title,
                        artist=artist,
                        album=album,
                        year=year,
                        last_modified=last_modified
                    ))
            
            logger.info(f"Loaded {len(music_files)} files from cache")
            return music_files
            
        except Exception as e:
            logger.error(f"Error loading cached files: {e}")
            return []

    def filter_by_genre(self, music_files: List[MusicFile], target_genre: str) -> List[MusicFile]:
        """Filter music files by genre"""
        target_genre = target_genre.lower().strip()
        
        # Get genre variations
        genre_variations = self.genre_mappings.get(target_genre, [target_genre])
        
        filtered_files = []
        
        for music_file in music_files:
            if music_file.genre:
                # Check if any genre variation matches
                for variation in genre_variations:
                    if variation in music_file.genre.lower():
                        filtered_files.append(music_file)
                        break
        
        logger.info(f"Found {len(filtered_files)} files matching genre '{target_genre}'")
        return filtered_files

    def select_random_files(self, music_files: List[MusicFile], target_size: int) -> List[MusicFile]:
        """Randomly select files up to target size"""
        selected_files = []
        current_size = 0
        
        # Shuffle files for random selection
        random.shuffle(music_files)
        
        for music_file in music_files:
            if current_size + music_file.size <= target_size:
                selected_files.append(music_file)
                current_size += music_file.size
            else:
                # Check if this single file would exceed target
                if music_file.size <= target_size:
                    # If it's close, include it anyway
                    selected_files.append(music_file)
                    current_size += music_file.size
                break
        
        logger.info(f"Selected {len(selected_files)} random files ({self.format_size(current_size)})")
        return selected_files

    def select_files_by_size(self, music_files: List[MusicFile], target_size: int) -> List[MusicFile]:
        """Select files up to target size (in order)"""
        selected_files = []
        current_size = 0
        
        for music_file in music_files:
            if current_size + music_file.size <= target_size:
                selected_files.append(music_file)
                current_size += music_file.size
            else:
                break
        
        logger.info(f"Selected {len(selected_files)} files ({self.format_size(current_size)})")
        return selected_files

    def copy_files(self, selected_files: List[MusicFile], dest_dir: Path) -> Tuple[int, int]:
        """Copy selected files to destination directory"""
        dest_dir.mkdir(parents=True, exist_ok=True)
        
        copied_count = 0
        copied_size = 0
        
        for i, music_file in enumerate(selected_files, 1):
            try:
                # Create destination path
                dest_path = dest_dir / music_file.path.name
                
                # Handle duplicates
                counter = 1
                original_dest = dest_path
                while dest_path.exists():
                    stem = original_dest.stem
                    suffix = original_dest.suffix
                    dest_path = dest_dir / f"{stem}_{counter}{suffix}"
                    counter += 1
                
                # Copy file
                shutil.copy2(music_file.path, dest_path)
                
                copied_count += 1
                copied_size += music_file.size
                
                logger.info(f"[{i}/{len(selected_files)}] Copied: {music_file.path.name} ({self.format_size(music_file.size)})")
                
            except Exception as e:
                logger.error(f"Failed to copy {music_file.path}: {e}")
        
        return copied_count, copied_size

    def format_size(self, size_bytes: int) -> str:
        """Format size in human readable format"""
        for unit in ['B', 'KB', 'MB', 'GB']:
            if size_bytes < 1024.0:
                return f"{size_bytes:.1f} {unit}"
            size_bytes /= 1024.0
        return f"{size_bytes:.1f} TB"

    def generate_report(self, selected_files: List[MusicFile], copied_count: int, copied_size: int, dest_dir: Path):
        """Generate a detailed report of the collection"""
        report_path = dest_dir / "collection_report.txt"
        
        with open(report_path, 'w', encoding='utf-8') as f:
            f.write("MUSIC COLLECTION REPORT\n")
            f.write("=" * 50 + "\n\n")
            f.write(f"Collection Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write(f"Destination: {dest_dir}\n")
            f.write(f"Files Copied: {copied_count}\n")
            f.write(f"Total Size: {self.format_size(copied_size)}\n\n")
            
            # Genre breakdown
            genre_counts = {}
            for music_file in selected_files:
                genre = music_file.genre or "Unknown"
                genre_counts[genre] = genre_counts.get(genre, 0) + 1
            
            f.write("GENRE BREAKDOWN:\n")
            f.write("-" * 20 + "\n")
            for genre, count in sorted(genre_counts.items(), key=lambda x: x[1], reverse=True):
                f.write(f"{genre}: {count} files\n")
            
            f.write("\nFILE LIST:\n")
            f.write("-" * 20 + "\n")
            for i, music_file in enumerate(selected_files, 1):
                f.write(f"{i:3d}. {music_file.path.name}\n")
                if music_file.title or music_file.artist:
                    f.write(f"     Title: {music_file.title or 'Unknown'}\n")
                    f.write(f"     Artist: {music_file.artist or 'Unknown'}\n")
                    f.write(f"     Album: {music_file.album or 'Unknown'}\n")
                    f.write(f"     Genre: {music_file.genre or 'Unknown'}\n")
                    f.write(f"     Size: {self.format_size(music_file.size)}\n")
                    f.write("\n")
        
        logger.info(f"Report saved to: {report_path}")

def main():
    parser = argparse.ArgumentParser(description="Collect music files by genre and size")
    parser.add_argument("--source", required=True, help="Source directory to scan")
    parser.add_argument("--dest", required=True, help="Destination directory for copied files")
    parser.add_argument("--genre", help="Target genre (e.g., country, rock, jazz)")
    parser.add_argument("--random", action="store_true", help="Select files randomly")
    parser.add_argument("--size", required=True, help="Target size (e.g., 1gb, 500mb)")
    parser.add_argument("--max-files", type=int, help="Maximum number of files to scan")
    parser.add_argument("--ffmpeg-path", help="Path to ffmpeg directory")
    parser.add_argument("--force-rescan", action="store_true", help="Force rescan all files (ignore cache)")
    parser.add_argument("--cache-only", action="store_true", help="Use only cached data (no file scanning)")
    
    args = parser.parse_args()
    
    # Validate arguments
    if not args.genre and not args.random:
        logger.error("Must specify either --genre or --random")
        sys.exit(1)
    
    source_dir = Path(args.source)
    if not source_dir.exists():
        logger.error(f"Source directory does not exist: {source_dir}")
        sys.exit(1)
    
    dest_dir = Path(args.dest)
    
    # Parse target size
    try:
        target_size = MusicCollector().parse_size(args.size)
    except ValueError as e:
        logger.error(f"Invalid size format: {e}")
        sys.exit(1)
    
    # Initialize collector
    try:
        collector = MusicCollector(args.ffmpeg_path)
    except FileNotFoundError as e:
        logger.error(f"ffprobe not found: {e}")
        logger.error("Please ensure ffprobe.exe is in the specified directory")
        sys.exit(1)
    
    logger.info(f"Target size: {collector.format_size(target_size)}")
    
    # Scan directory
    music_files = collector.scan_directory(source_dir, args.max_files, args.force_rescan, args.cache_only)
    
    if not music_files:
        logger.error("No MP3 files found with metadata")
        sys.exit(1)
    
    # Filter or select files
    if args.genre:
        selected_files = collector.filter_by_genre(music_files, args.genre)
        if not selected_files:
            logger.error(f"No files found matching genre: {args.genre}")
            sys.exit(1)
    else:
        # Random selection
        selected_files = collector.select_random_files(music_files, target_size)
    
    # If genre filtering was used, select up to target size
    if args.genre:
        selected_files = collector.select_files_by_size(selected_files, target_size)
    
    if not selected_files:
        logger.error("No files selected for copying")
        sys.exit(1)
    
    # Copy files
    logger.info(f"Copying {len(selected_files)} files to {dest_dir}")
    copied_count, copied_size = collector.copy_files(selected_files, dest_dir)
    
    # Generate report
    collector.generate_report(selected_files, copied_count, copied_size, dest_dir)
    
    logger.info(f"Collection complete!")
    logger.info(f"Copied {copied_count} files ({collector.format_size(copied_size)})")
    logger.info(f"Destination: {dest_dir}")

if __name__ == "__main__":
    main() 