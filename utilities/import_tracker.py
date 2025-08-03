#!/usr/bin/env python3
"""
Music Archive Import Tracker Module

This module provides comprehensive tracking functionality for bulk imports.
It can be used by any upload script to provide uniform tracking capabilities.

Features:
- SQLite database tracking for import jobs and file processing
- Resume capability for interrupted imports
- Detailed error reporting and recovery
- Cross-script compatibility (multiple scripts can use same tracking DB)
- Comprehensive statistics and reporting

Usage:
    from import_tracker import BulkImportTracker
    
    tracker = BulkImportTracker('import_tracking.db')
    tracker.start_job(len(files), command_line)
    
    for filepath in files:
        file_id = tracker.record_file_start(filepath)
        # ... upload file ...
        if success:
            tracker.record_file_success(file_id, song_id=song_id)
        else:
            tracker.record_file_failure(file_id, error_msg, error_type)
    
    tracker.complete_job()
"""

import sqlite3
import datetime
import os
import json
from typing import List, Optional, Tuple, Dict, Any


class BulkImportTracker:
    """Comprehensive tracking system for bulk imports using SQLite."""
    
    def __init__(self, db_path: str):
        """
        Initialize the tracker with a SQLite database.
        
        Args:
            db_path: Path to the SQLite database file
        """
        self.db_path = db_path
        self.job_id = None
        self.conn = None
        self._ensure_db_exists()
    
    def _ensure_db_exists(self):
        """Create database and tables if they don't exist."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Import jobs table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS import_jobs (
                id INTEGER PRIMARY KEY,
                started_at TIMESTAMP,
                completed_at TIMESTAMP,
                status TEXT,
                total_files INTEGER,
                processed_files INTEGER,
                failed_files INTEGER,
                notes TEXT,
                command_line TEXT,
                script_name TEXT,
                upload_method TEXT
            )
        ''')
        
        # File imports table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS file_imports (
                id INTEGER PRIMARY KEY,
                job_id INTEGER,
                file_path TEXT,
                file_id_key TEXT,
                status TEXT,
                error_message TEXT,
                error_type TEXT,
                error_details TEXT,
                metadata_extracted BOOLEAN,
                file_uploaded BOOLEAN,
                created_at TIMESTAMP,
                updated_at TIMESTAMP,
                file_size INTEGER,
                duration REAL,
                format TEXT,
                processing_time REAL,
                song_id TEXT,
                response_status TEXT,
                upload_method TEXT
            )
        ''')
        
        # Add file_id_key column if it doesn't exist (for existing databases)
        try:
            cursor.execute('ALTER TABLE file_imports ADD COLUMN file_id_key TEXT')
        except sqlite3.OperationalError:
            # Column already exists
            pass
        
        # Create indexes for better performance
        cursor.execute('''
            CREATE INDEX IF NOT EXISTS idx_file_imports_job_id 
            ON file_imports(job_id)
        ''')
        
        cursor.execute('''
            CREATE INDEX IF NOT EXISTS idx_file_imports_status 
            ON file_imports(status)
        ''')
        
        cursor.execute('''
            CREATE INDEX IF NOT EXISTS idx_file_imports_file_path 
            ON file_imports(file_path)
        ''')
        
        conn.commit()
        conn.close()
    
    def start_job(self, total_files: int, command_line: str, script_name: str = "unknown", 
                  upload_method: str = "unknown", notes: str = None):
        """
        Start a new import job.
        
        Args:
            total_files: Total number of files to process
            command_line: Full command line used for the import
            script_name: Name of the script (e.g., 'bulk_upload', 'universal_upload')
            upload_method: Method used for upload (e.g., 'rails_api', 'direct_fs')
            notes: Optional notes about the job
        """
        self.conn = sqlite3.connect(self.db_path)
        cursor = self.conn.cursor()
        
        cursor.execute('''
            INSERT INTO import_jobs (
                started_at, status, total_files, processed_files, failed_files, 
                command_line, script_name, upload_method, notes
            )
            VALUES (?, 'running', ?, 0, 0, ?, ?, ?, ?)
        ''', (datetime.datetime.now(), total_files, command_line, script_name, upload_method, notes))
        
        self.job_id = cursor.lastrowid
        self.conn.commit()
        print(f"📊 Started import job {self.job_id} with {total_files} files")
        print(f"   Script: {script_name}, Method: {upload_method}")
    
    def record_file_start(self, file_path: str) -> int:
        """
        Record the start of processing a file.
        
        Args:
            file_path: Full path to the file being processed
            
        Returns:
            File import ID for tracking this specific file, or -1 if already processed
        """
        # Ensure connection exists
        if self.conn is None:
            self.conn = sqlite3.connect(self.db_path)
            
        cursor = self.conn.cursor()
        
        # Get unique file identifier (inode + device)
        try:
            stat = os.stat(file_path)
            file_id_key = f"{stat.st_dev}:{stat.st_ino}"
        except OSError:
            # Fallback to path if stat fails
            file_id_key = file_path
        
        # Check if file was already processed successfully by unique ID - NEVER REPROCESS
        cursor.execute('''
            SELECT id FROM file_imports 
            WHERE file_id_key = ? AND status = 'success'
        ''', (file_id_key,))
        
        existing = cursor.fetchone()
        if existing:
            # File was already successfully processed - SKIP IT
            return -1
        
        # Check if file is currently being processed
        cursor.execute('''
            SELECT id FROM file_imports 
            WHERE file_id_key = ? AND status = 'processing'
        ''', (file_id_key,))
        
        existing = cursor.fetchone()
        if existing:
            # File is already being processed, return existing ID
            return existing[0]
        
        # Create new record with unique file identifier
        cursor.execute('''
            INSERT INTO file_imports (job_id, file_path, file_id_key, status, created_at)
            VALUES (?, ?, ?, 'processing', ?)
        ''', (self.job_id or 0, file_path, file_id_key, datetime.datetime.now()))
        return cursor.lastrowid
    
    def record_file_success(self, file_id: int, metadata_extracted: bool = True, 
                           file_uploaded: bool = True, file_size: Optional[int] = None,
                           duration: Optional[float] = None, format_type: Optional[str] = None,
                           processing_time: Optional[float] = None, song_id: Optional[str] = None,
                           response_status: Optional[str] = None, upload_method: Optional[str] = None):
        """
        Record successful file processing.
        
        Args:
            file_id: ID returned from record_file_start()
            metadata_extracted: Whether metadata was extracted
            file_uploaded: Whether file was uploaded
            file_size: Size of the file in bytes
            duration: Duration of the audio file
            format_type: Audio format (mp3, flac, etc.)
            processing_time: Time taken to process the file
            song_id: ID of the song in the database
            response_status: HTTP response status
            upload_method: Method used for upload
        """
        # Ensure connection exists
        if self.conn is None:
            self.conn = sqlite3.connect(self.db_path)
            
        cursor = self.conn.cursor()
        cursor.execute('''
            UPDATE file_imports 
            SET status = 'success', metadata_extracted = ?, file_uploaded = ?, 
                updated_at = ?, file_size = ?, duration = ?, format = ?, processing_time = ?,
                song_id = ?, response_status = ?, upload_method = ?
            WHERE id = ?
        ''', (metadata_extracted, file_uploaded, datetime.datetime.now(), 
              file_size, duration, format_type, processing_time, song_id, response_status, 
              upload_method, file_id))
        
        # Only update job stats if we have a valid job_id
        if self.job_id:
            cursor.execute('''
                UPDATE import_jobs 
                SET processed_files = processed_files + 1
                WHERE id = ?
            ''', (self.job_id,))
        
        self.conn.commit()
    
    def record_file_failure(self, file_id: int, error_message: str, 
                           error_type: Optional[str] = None, error_details: Optional[str] = None,
                           upload_method: Optional[str] = None):
        """
        Record file processing failure.
        
        Args:
            file_id: ID returned from record_file_start()
            error_message: Human-readable error message
            error_type: Type of error (e.g., 'UPLOAD_ERROR', 'NETWORK_ERROR')
            error_details: Detailed error information (stack trace, etc.)
            upload_method: Method used for upload
        """
        # Ensure connection exists
        if self.conn is None:
            self.conn = sqlite3.connect(self.db_path)
            
        cursor = self.conn.cursor()
        cursor.execute('''
            UPDATE file_imports 
            SET status = 'failed', error_message = ?, error_type = ?, error_details = ?, 
                updated_at = ?, upload_method = ?
            WHERE id = ?
        ''', (error_message, error_type, error_details, datetime.datetime.now(), upload_method, file_id))
        
        # Only update job stats if we have a valid job_id
        if self.job_id:
            cursor.execute('''
                UPDATE import_jobs 
                SET failed_files = failed_files + 1
                WHERE id = ?
            ''', (self.job_id,))
        
        self.conn.commit()
    
    def get_resume_info(self) -> Optional[Tuple]:
        """
        Get info about the last job for resuming.
        
        Returns:
            Tuple of (job_id, processed_files, failed_files, total_files, status) or None
        """
        cursor = self.conn.cursor()
        cursor.execute('''
            SELECT id, processed_files, failed_files, total_files, status, script_name, upload_method
            FROM import_jobs 
            ORDER BY started_at DESC 
            LIMIT 1
        ''')
        return cursor.fetchone()
    
    def get_processed_files(self, job_id: Optional[int] = None) -> List[str]:
        """
        Get list of already processed files.
        
        Args:
            job_id: Job ID to check (uses current job if None, or ALL jobs if job_id is 'all')
            
        Returns:
            List of file paths that were successfully processed
        """
        # If no connection exists, return empty list (no files processed yet)
        if self.conn is None:
            return []
            
        cursor = self.conn.cursor()
        
        # If job_id is 'all' or None, get all processed files from all jobs
        if job_id is None or job_id == 'all':
            cursor.execute('''
                SELECT file_path FROM file_imports 
                WHERE status = 'success'
            ''')
        else:
            cursor.execute('''
                SELECT file_path FROM file_imports 
                WHERE job_id = ? AND status = 'success'
            ''', (job_id,))
            
        return [row[0] for row in cursor.fetchall()]
    
    def is_file_processed(self, file_path: str) -> bool:
        """
        Check if a specific file has been processed by its unique identifier.
        
        Args:
            file_path: Full path to the file
            
        Returns:
            True if file was successfully processed, False otherwise
        """
        # Ensure connection exists
        if self.conn is None:
            self.conn = sqlite3.connect(self.db_path)
            
        cursor = self.conn.cursor()
        
        # Get unique file identifier (inode + device)
        try:
            stat = os.stat(file_path)
            file_id_key = f"{stat.st_dev}:{stat.st_ino}"
        except OSError:
            # Fallback to path if stat fails
            file_id_key = file_path
        
        cursor.execute('''
            SELECT id FROM file_imports 
            WHERE file_id_key = ? AND status = 'success'
        ''', (file_id_key,))
        
        return cursor.fetchone() is not None
    
    def get_failed_files(self, job_id: Optional[int] = None) -> List[Tuple[str, str, str]]:
        """
        Get list of failed files with error information.
        
        Args:
            job_id: Job ID to check (uses current job if None)
            
        Returns:
            List of tuples (file_path, error_message, error_type)
        """
        # If no connection exists, return empty list
        if self.conn is None:
            return []
            
        cursor = self.conn.cursor()
        if job_id is None:
            job_id = self.job_id
        
        cursor.execute('''
            SELECT file_path, error_message, error_type FROM file_imports 
            WHERE job_id = ? AND status = 'failed'
        ''', (job_id,))
        return cursor.fetchall()
    
    def get_job_stats(self, job_id: Optional[int] = None) -> Tuple[int, int, int, int]:
        """
        Get comprehensive stats for a job.
        
        Args:
            job_id: Job ID to check (uses current job if None)
            
        Returns:
            Tuple of (total, success, failed, processing)
        """
        # If no connection exists, return zeros
        if self.conn is None:
            return (0, 0, 0, 0)
            
        cursor = self.conn.cursor()
        if job_id is None:
            job_id = self.job_id
        
        cursor.execute('''
            SELECT 
                COUNT(*) as total,
                SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) as success,
                SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as failed,
                SUM(CASE WHEN status = 'processing' THEN 1 ELSE 0 END) as processing
            FROM file_imports 
            WHERE job_id = ?
        ''', (job_id,))
        return cursor.fetchone()
    
    def get_all_jobs(self) -> List[Dict[str, Any]]:
        """
        Get all import jobs with their statistics.
        
        Returns:
            List of job dictionaries with stats
        """
        cursor = self.conn.cursor()
        cursor.execute('''
            SELECT 
                j.id, j.started_at, j.completed_at, j.status, j.total_files,
                j.processed_files, j.failed_files, j.script_name, j.upload_method,
                j.command_line, j.notes
            FROM import_jobs j
            ORDER BY j.started_at DESC
        ''')
        
        jobs = []
        for row in cursor.fetchall():
            jobs.append({
                'id': row[0],
                'started_at': row[1],
                'completed_at': row[2],
                'status': row[3],
                'total_files': row[4],
                'processed_files': row[5],
                'failed_files': row[6],
                'script_name': row[7],
                'upload_method': row[8],
                'command_line': row[9],
                'notes': row[10]
            })
        
        return jobs
    
    def show_error_summary(self, job_id: Optional[int] = None):
        """
        Show quick error summary.
        
        Args:
            job_id: Job ID to check (uses current job if None)
        """
        cursor = self.conn.cursor()
        if job_id is None:
            job_id = self.job_id
        
        cursor.execute('''
            SELECT error_type, COUNT(*) as count
            FROM file_imports 
            WHERE job_id = ? AND status = 'failed'
            GROUP BY error_type
            ORDER BY count DESC
        ''', (job_id,))
        
        print("=== ERROR SUMMARY ===")
        results = cursor.fetchall()
        if not results:
            print("No errors found.")
            return
        
        for error_type, count in results:
            print(f"{error_type or 'Unknown'}: {count} files")
    
    def show_errors_verbose(self, job_id: Optional[int] = None):
        """
        Show detailed error information.
        
        Args:
            job_id: Job ID to check (uses current job if None)
        """
        cursor = self.conn.cursor()
        if job_id is None:
            job_id = self.job_id
        
        cursor.execute('''
            SELECT file_path, error_message, error_type, error_details, created_at
            FROM file_imports 
            WHERE job_id = ? AND status = 'failed'
            ORDER BY created_at DESC
        ''', (job_id,))
        
        print("=== DETAILED ERROR REPORT ===")
        results = cursor.fetchall()
        if not results:
            print("No errors found.")
            return
        
        for file_path, error_msg, error_type, error_details, created_at in results:
            print(f"\nFile: {file_path}")
            print(f"Error: {error_msg}")
            print(f"Type: {error_type or 'Unknown'}")
            if error_details:
                print(f"Details: {error_details}")
            print(f"Time: {created_at}")
            print("-" * 50)
    
    def show_job_summary(self, job_id: Optional[int] = None):
        """
        Show summary of a specific job.
        
        Args:
            job_id: Job ID to check (uses current job if None)
        """
        if job_id is None:
            job_id = self.job_id
        
        cursor = self.conn.cursor()
        cursor.execute('''
            SELECT started_at, completed_at, status, total_files, processed_files, 
                   failed_files, script_name, upload_method, command_line
            FROM import_jobs 
            WHERE id = ?
        ''', (job_id,))
        
        job = cursor.fetchone()
        if not job:
            print(f"Job {job_id} not found.")
            return
        
        started_at, completed_at, status, total_files, processed_files, failed_files, script_name, upload_method, command_line = job
        
        print(f"=== JOB {job_id} SUMMARY ===")
        print(f"Script: {script_name}")
        print(f"Method: {upload_method}")
        print(f"Status: {status}")
        print(f"Started: {started_at}")
        if completed_at:
            print(f"Completed: {completed_at}")
        print(f"Files: {processed_files}/{total_files} processed, {failed_files} failed")
        print(f"Command: {command_line}")
        
        # Show stats
        total, success, failed, processing = self.get_job_stats(job_id)
        print(f"Current: {success} success, {failed} failed, {processing} processing")
    
    def complete_job(self):
        """Mark job as completed."""
        cursor = self.conn.cursor()
        cursor.execute('''
            UPDATE import_jobs 
            SET status = 'completed', completed_at = ?
            WHERE id = ?
        ''', (datetime.datetime.now(), self.job_id))
        self.conn.commit()
        self.conn.close()
        print(f"✅ Import job {self.job_id} completed")
    
    def close(self):
        """Close the database connection."""
        if self.conn:
            self.conn.close()


def get_script_name() -> str:
    """Get the name of the calling script."""
    import sys
    script_path = sys.argv[0]
    return os.path.basename(script_path)


def get_upload_method(script_name: str) -> str:
    """Determine upload method based on script name."""
    if 'bulk_upload' in script_name:
        return 'rails_api'
    elif 'universal_upload' in script_name:
        return 'direct_fs'
    else:
        return 'unknown'


# Convenience functions for common operations
def create_tracker(db_path: str = 'import_tracking.db') -> BulkImportTracker:
    """Create a tracker instance with default settings."""
    return BulkImportTracker(db_path)


def start_job_with_defaults(tracker: BulkImportTracker, total_files: int, 
                           command_line: str = None, notes: str = None) -> None:
    """Start a job with default script detection."""
    if command_line is None:
        import sys
        command_line = ' '.join(sys.argv)
    
    script_name = get_script_name()
    upload_method = get_upload_method(script_name)
    
    tracker.start_job(total_files, command_line, script_name, upload_method, notes)


def resume_from_last_job(tracker: BulkImportTracker, files: List[str]) -> List[str]:
    """
    Resume from the last job, filtering out already processed files.
    
    Args:
        tracker: Tracker instance
        files: List of files to process
        
    Returns:
        List of files that still need processing
    """
    resume_info = tracker.get_resume_info()
    if resume_info:
        job_id, processed, failed, total_prev, status, script_name, upload_method = resume_info
        print(f"🔄 Resuming from job {job_id}: {processed} processed, {failed} failed")
        print(f"   Script: {script_name}, Method: {upload_method}")
        
        processed_files = set(tracker.get_processed_files(job_id))
        remaining_files = [f for f in files if f not in processed_files]
        print(f"📁 {len(remaining_files)} files remaining to process")
        return remaining_files
    else:
        print("ℹ️  No previous job found, starting fresh")
        return files


def show_all_jobs(db_path: str = 'import_tracking.db'):
    """Show summary of all jobs in the database."""
    tracker = BulkImportTracker(db_path)
    jobs = tracker.get_all_jobs()
    
    if not jobs:
        print("No jobs found in database.")
        return
    
    print("=== ALL IMPORT JOBS ===")
    for job in jobs:
        print(f"\nJob {job['id']}: {job['script_name']} ({job['upload_method']})")
        print(f"  Status: {job['status']}")
        print(f"  Files: {job['processed_files']}/{job['total_files']} processed, {job['failed_files']} failed")
        print(f"  Started: {job['started_at']}")
        if job['completed_at']:
            print(f"  Completed: {job['completed_at']}")


if __name__ == "__main__":
    # Test the module
    print("Testing Import Tracker Module...")
    
    # Create tracker
    tracker = BulkImportTracker('test_tracking.db')
    
    # Test job creation
    tracker.start_job(10, "test command", "test_script", "test_method")
    
    # Test file tracking
    file_id = tracker.record_file_start("/test/file.mp3")
    tracker.record_file_success(file_id, song_id="test_123")
    
    file_id2 = tracker.record_file_start("/test/file2.mp3")
    tracker.record_file_failure(file_id2, "Test error", "TEST_ERROR")
    
    # Show results
    tracker.show_error_summary()
    tracker.complete_job()
    
    # Cleanup
    if os.path.exists('test_tracking.db'):
        os.remove('test_tracking.db')
    
    print("✅ Module test completed!") 