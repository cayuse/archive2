#!/usr/bin/env python3
"""
Music Archive Tracking Utilities

This script provides utilities for managing and querying the import tracking database.
It demonstrates the shared tracking functionality and provides useful commands.

Usage:
    python3 track_utils.py [command] [options]

Commands:
    show-all              Show all import jobs
    show-job <job_id>     Show details of a specific job
    show-errors [job_id]  Show error summary (all jobs or specific job)
    show-verbose [job_id] Show detailed error report
    list-failed [job_id]  List all failed files
    list-success [job_id] List all successful files
    stats                 Show overall statistics
    cleanup               Remove old tracking data
    export <job_id>       Export job data to JSON

Examples:
    python3 track_utils.py show-all
    python3 track_utils.py show-job 1
    python3 track_utils.py show-errors
    python3 track_utils.py show-verbose 2
    python3 track_utils.py stats
"""

import sys
import argparse
import json
from datetime import datetime, timedelta
from import_tracker import BulkImportTracker, show_all_jobs


def show_job_details(tracker, job_id):
    """Show detailed information about a specific job."""
    tracker.show_job_summary(job_id)


def show_failed_files(tracker, job_id=None):
    """List all failed files with their error information."""
    failed_files = tracker.get_failed_files(job_id)
    
    if not failed_files:
        print("No failed files found.")
        return
    
    print(f"=== FAILED FILES {'(Job ' + str(job_id) + ')' if job_id else '(All Jobs)'} ===")
    for file_path, error_msg, error_type in failed_files:
        print(f"\nFile: {file_path}")
        print(f"Error: {error_msg}")
        print(f"Type: {error_type or 'Unknown'}")
        print("-" * 40)


def show_successful_files(tracker, job_id=None):
    """List all successful files."""
    successful_files = tracker.get_processed_files(job_id)
    
    if not successful_files:
        print("No successful files found.")
        return
    
    print(f"=== SUCCESSFUL FILES {'(Job ' + str(job_id) + ')' if job_id else '(All Jobs)'} ===")
    for file_path in successful_files:
        print(f"✓ {file_path}")


def show_overall_stats(tracker):
    """Show overall statistics across all jobs."""
    jobs = tracker.get_all_jobs()
    
    if not jobs:
        print("No jobs found in database.")
        return
    
    total_jobs = len(jobs)
    completed_jobs = len([j for j in jobs if j['status'] == 'completed'])
    running_jobs = len([j for j in jobs if j['status'] == 'running'])
    
    total_files = sum(j['total_files'] for j in jobs)
    total_processed = sum(j['processed_files'] for j in jobs)
    total_failed = sum(j['failed_files'] for j in jobs)
    
    print("=== OVERALL STATISTICS ===")
    print(f"Total Jobs: {total_jobs}")
    print(f"  Completed: {completed_jobs}")
    print(f"  Running: {running_jobs}")
    print(f"  Other: {total_jobs - completed_jobs - running_jobs}")
    print()
    print(f"Total Files: {total_files}")
    print(f"  Processed: {total_processed}")
    print(f"  Failed: {total_failed}")
    print(f"  Success Rate: {(total_processed / total_files * 100):.1f}%" if total_files > 0 else "  Success Rate: N/A")
    
    # Show upload method breakdown
    methods = {}
    for job in jobs:
        method = job['upload_method']
        methods[method] = methods.get(method, 0) + 1
    
    print("\nUpload Methods:")
    for method, count in methods.items():
        print(f"  {method}: {count} jobs")


def cleanup_old_data(tracker, days=30):
    """Remove tracking data older than specified days."""
    cutoff_date = datetime.now() - timedelta(days=days)
    
    # This would require additional functionality in the tracker
    # For now, just show what would be cleaned up
    jobs = tracker.get_all_jobs()
    old_jobs = [j for j in jobs if j['started_at'] and datetime.fromisoformat(j['started_at'].replace('Z', '+00:00')) < cutoff_date]
    
    print(f"=== CLEANUP (Jobs older than {days} days) ===")
    if old_jobs:
        print(f"Found {len(old_jobs)} old jobs:")
        for job in old_jobs:
            print(f"  Job {job['id']}: {job['started_at']} ({job['script_name']})")
        print("\nNote: Cleanup functionality not yet implemented.")
    else:
        print("No old jobs found.")


def export_job_data(tracker, job_id, output_file=None):
    """Export job data to JSON format."""
    if output_file is None:
        output_file = f"job_{job_id}_export.json"
    
    # Get job details
    jobs = tracker.get_all_jobs()
    job = next((j for j in jobs if j['id'] == job_id), None)
    
    if not job:
        print(f"Job {job_id} not found.")
        return
    
    # Get file details
    successful_files = tracker.get_processed_files(job_id)
    failed_files = tracker.get_failed_files(job_id)
    
    export_data = {
        'job': job,
        'successful_files': successful_files,
        'failed_files': [{'file_path': f[0], 'error_message': f[1], 'error_type': f[2]} for f in failed_files],
        'export_date': datetime.now().isoformat(),
        'export_version': '1.0'
    }
    
    with open(output_file, 'w') as f:
        json.dump(export_data, f, indent=2)
    
    print(f"Exported job {job_id} data to {output_file}")


def main():
    parser = argparse.ArgumentParser(description="Music Archive Tracking Utilities")
    parser.add_argument('command', help='Command to execute')
    parser.add_argument('job_id', nargs='?', type=int, help='Job ID (for commands that need it)')
    parser.add_argument('--db', default='import_tracking.db', help='Tracking database path')
    parser.add_argument('--output', help='Output file for export command')
    parser.add_argument('--days', type=int, default=30, help='Days for cleanup command')
    
    args = parser.parse_args()
    
    # Initialize tracker
    tracker = BulkImportTracker(args.db)
    
    if args.command == 'show-all':
        show_all_jobs(args.db)
    
    elif args.command == 'show-job':
        if not args.job_id:
            print("Error: Job ID required for show-job command")
            sys.exit(1)
        show_job_details(tracker, args.job_id)
    
    elif args.command == 'show-errors':
        if args.job_id:
            tracker.show_error_summary(args.job_id)
        else:
            tracker.show_error_summary()
    
    elif args.command == 'show-verbose':
        if args.job_id:
            tracker.show_errors_verbose(args.job_id)
        else:
            tracker.show_errors_verbose()
    
    elif args.command == 'list-failed':
        show_failed_files(tracker, args.job_id)
    
    elif args.command == 'list-success':
        show_successful_files(tracker, args.job_id)
    
    elif args.command == 'stats':
        show_overall_stats(tracker)
    
    elif args.command == 'cleanup':
        cleanup_old_data(tracker, args.days)
    
    elif args.command == 'export':
        if not args.job_id:
            print("Error: Job ID required for export command")
            sys.exit(1)
        export_job_data(tracker, args.job_id, args.output)
    
    else:
        print(f"Unknown command: {args.command}")
        print("Available commands: show-all, show-job, show-errors, show-verbose, list-failed, list-success, stats, cleanup, export")
        sys.exit(1)


if __name__ == "__main__":
    main() 