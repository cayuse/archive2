# The Archive: utilities

Scripts for uploading audio files in bulk to The Archive, plus a few tag-inspection tools.

Both upload scripts work the same way: log in with `POST /api/v1/auth/login` (a moderator or
admin account), walk a directory, and send each file to `POST /api/v1/songs/bulk_upload`.
The archive reads the tags and stores the file. The endpoint is described in
`../docs/reference/archive_api.md` and `../docs/reference/BULK_OPERATIONS_AND_API.md`.

## Shared Tracking Module

### `import_tracker.py` - Shared Tracking Module

A SQLite-based tracking module that both upload scripts use.

**Features:**
- **Cross-Script Compatibility**: Both upload scripts use the same tracking database
- **Resume Capability**: Can resume interrupted imports from any script
- **Detailed Error Tracking**: Comprehensive error reporting and recovery
- **Performance Monitoring**: Track processing time, file sizes, and upload methods
- **Flexible Querying**: Rich API for querying job and file statistics

**Usage:**
```python
from import_tracker import BulkImportTracker, start_job_with_defaults, resume_from_last_job

# Create tracker
tracker = BulkImportTracker('import_tracking.db')

# Start job with automatic script detection
start_job_with_defaults(tracker, len(files))

# Resume from last job
remaining_files = resume_from_last_job(tracker, all_files)

# Track file processing
file_id = tracker.record_file_start(filepath)
tracker.record_file_success(file_id, song_id=song_id)
# or
tracker.record_file_failure(file_id, error_msg, error_type)
```

## Upload Scripts

### 1. Bulk Upload Script (`bulk_upload.py`)

Uploads audio files one at a time through the API, with tracking, resume and error reporting.

**Features:**
- **Rails API Integration**: Uploads through Rails API endpoints
- **Tracking**: Uses shared SQLite tracking module
- **Resume Capability**: Can resume interrupted imports from where they left off
- **Error Reporting**: Detailed error tracking with quick summaries and verbose reports
- **Batch Processing**: Support for processing files in batches for testing
- **Graceful Shutdown**: Can be stopped gracefully with 'q' key or Ctrl+C
- **Progress Monitoring**: Real-time progress with detailed statistics

### 2. Universal Upload Script (`universal_upload.py`)

Uploads through the same API endpoint as `bulk_upload.py`, several files at a time, and is
more defensive about paths and file names. It does not write to the archive's storage
directly (the tracking database labels its uploads `direct_fs` for historical reasons).

**Features:**
- **Rails API Integration**: Uploads through `POST /api/v1/songs/bulk_upload`
- **Cross-platform Compatibility**: Works across Linux, Mac, Windows
- **Full Unicode Support**: Handles any Unicode characters, spaces, special characters
- **Concurrent Uploads**: Configurable concurrent upload limits
- **Tracking**: Uses shared SQLite tracking module
- **Resume Capability**: Can resume interrupted imports
- **Error Reporting**: Detailed error tracking and recovery
- **Robust Path Handling**: Normalizes paths for any filesystem

## Usage

### Bulk Upload (one file at a time)
```bash
# Start fresh import
python3 bulk_upload.py ~/Music --start-over --verbose

# Resume from where it left off
python3 bulk_upload.py ~/Music --resume

# Test with first 100 files
python3 bulk_upload.py ~/Music --max-count 100

# Show error summary
python3 bulk_upload.py ~/Music --show-errors
```

### Universal Upload (concurrent)
```bash
# Start fresh import with concurrent uploads
python3 universal_upload.py ~/Music --start-over --concurrent 10 --verbose

# Resume from where it left off
python3 universal_upload.py ~/Music --resume

# Test with first 100 files
python3 universal_upload.py ~/Music --max-count 100

# Show error summary
python3 universal_upload.py ~/Music --show-errors
```

## Command Line Options

### Mode Options
- `--start-over`: Start fresh, ignore existing tracking data
- `--clear-db`: Clear the tracking database before starting
- `--resume`: Resume from last successful import
- `--show-errors`: Show error summary and exit
- `--show-errors-verbose`: Show detailed error information and exit

### Processing Limits
- `--max-count N`: Maximum number of files to process
- `--continue-from N`: Continue from this offset (for batch processing)
- `--batch-size N`: Batch size (see `--help`)

### Tracking Options
- `--tracking-db PATH`: SQLite database for tracking progress (default: import_tracking.db)

### Authentication Options
- `--url URL`: Base URL of the archive (default: http://localhost:3000)
- `--username USERNAME`: Username/email for authentication
- `--password PASSWORD`: Password for authentication (`universal_upload.py` prompts if it is omitted)

### Other Options
- `-d, --dry-run`: Show what would be uploaded without actually uploading
- `-v, --verbose`: Verbose output
- `--concurrent CONCURRENT`: Number of concurrent uploads (universal_upload.py only)
- `--limit LIMIT`: Limit upload to first N files (universal_upload.py only)

### Controls
- Press 'q': Stop gracefully after current upload completes
- Press Ctrl+C: Stop immediately

## Tracking Database

Both scripts use a shared SQLite database (`import_tracking.db` by default) to track:

### Import Jobs Table
- Job ID, start/complete times, status
- Total files, processed files, failed files
- Command line used for the import
- Script name and upload method

### File Imports Table
- Individual file processing status
- Error messages, types, and details
- Processing time, file size, format info
- Song ID and response status from API
- Upload method used

## Cross-Script Compatibility

Because the tracking database is shared, the scripts can be mixed:

### Mixed Upload Strategies
```bash
# Start with concurrent uploads
python3 universal_upload.py ~/Music --max-count 1000 --concurrent 10

# Carry on one file at a time
python3 bulk_upload.py ~/Music --resume
```

### Resume Across Scripts
- Both scripts can resume from the same tracking database
- Upload method is tracked and reported
- Can switch between scripts mid-import

### Unified Error Reporting
```bash
# Check errors from any script
python3 bulk_upload.py ~/Music --show-errors
python3 universal_upload.py ~/Music --show-errors
```

## Tracking Utilities

### `track_utils.py` - Tracking Management Script

A utility script for managing and querying the tracking database.

**Commands:**
```bash
# Show all import jobs
python3 track_utils.py show-all

# Show details of a specific job
python3 track_utils.py show-job 1

# Show error summary
python3 track_utils.py show-errors

# Show detailed error report
python3 track_utils.py show-verbose 2

# List failed files
python3 track_utils.py list-failed

# List successful files
python3 track_utils.py list-success

# Show overall statistics
python3 track_utils.py stats

# Export job data to JSON
python3 track_utils.py export 1 --output job_data.json
```

## Error Reporting

### Quick Summary
```bash
python3 bulk_upload.py ~/Music --show-errors
```
Shows error types and counts:
```
=== ERROR SUMMARY ===
UPLOAD_ERROR: 15 files
HTTP_422: 3 files
NETWORK_ERROR: 1 files
```

### Detailed Report
```bash
python3 bulk_upload.py ~/Music --show-errors-verbose
```
Shows full error details for each failed file.

## Resume Logic

Both scripts can resume interrupted imports by:

1. **Checking tracking database** for the last job
2. **Identifying processed files** from previous runs
3. **Skipping already uploaded files** to avoid duplicates
4. **Continuing from where it left off**

## Batch Processing

For large imports, you can process files in batches:

```bash
# Process first 1000 files
python3 bulk_upload.py ~/Music --max-count 1000

# Process next 1000 files
python3 bulk_upload.py ~/Music --continue-from 1000 --max-count 1000

# Continue with remaining files
python3 bulk_upload.py ~/Music --continue-from 2000
```

## Which script

Both go through the same endpoint, so the archive does the same work per file either way
(it reads the tags with `ffprobe` inside the upload request).

- `bulk_upload.py`: one upload at a time. Slower, gentlest on the server.
- `universal_upload.py`: `--concurrent N` uploads at once (default 5), and handles awkward
  paths (Windows/WSL, Unicode, odd characters) more carefully.

## Tag Extractor Scripts

### Standalone Tag Extractor (`standalone_tag_extractor.rb`)

A Ruby script for extracting metadata from audio files using both `wahwah` and `ffprobe`.

#### Features
- Extracts all possible metadata tags
- Uses `ffprobe` as fallback for comprehensive extraction
- Handles binary data gracefully
- Outputs in multiple formats (JSON, grep-friendly)
- Supports all major audio formats

#### Usage
```bash
ruby standalone_tag_extractor.rb <file_path>
```

#### Output Formats
- **JSON**: Complete metadata structure
- **Grep-friendly**: Simple key-value pairs for easy searching
- **Binary data handling**: Notes presence of binary data without displaying it

### Windows Tag Extractor (`windows_tag_extractor.rb`)

Specialized version for Windows environments with WSL compatibility.

### Storage Tag Extractor (`storage_tag_extractor.rb`)

Extracts metadata from files already uploaded to Active Storage.

## API Documentation

See `API_DOCUMENTATION.md` for the two endpoints these scripts use, and
`../docs/reference/archive_api.md` for the whole API.

## Test Scripts

- `test_api.sh`: Test API endpoints

## Requirements

- Python 3.6+
- Ruby 2.7+ (for tag extractors)
- ffmpeg/ffprobe (for comprehensive metadata extraction)
- The Archive running and reachable, and a moderator or admin account

## Troubleshooting

### Common Issues

1. **Authentication Errors**: Check username/password and API URL
2. **Network Errors**: Verify Rails server is running and accessible
3. **File Access Errors**: Ensure script has read permissions for audio files
4. **WSL File Access**: Use Windows paths or copy files into container

### Error Types

- `UPLOAD_ERROR`: General upload failures
- `HTTP_422`: Invalid file format or metadata issues
- `NETWORK_ERROR`: Connection problems
- `AUTHENTICATION_ERROR`: Login/authorization issues
- `FILE_ACCESS_ERROR`: File system access problems

### Debugging

1. Use `--verbose` for detailed output
2. Check error reports with `--show-errors-verbose`
3. Use `--dry-run` to test without uploading
4. Start with small batches using `--max-count`

## Benefits of Shared Tracking Module

### **1. Uniform Tracking**
- Both scripts use identical tracking logic
- Consistent error reporting and resume capabilities
- Same database schema and query interface

### **2. Cross-Script Resume**
- Can start with one script and resume with another
- Upload method is tracked and reported
- Seamless switching between upload strategies

### **3. Easier Maintenance**
- Single source of truth for tracking logic
- Bug fixes and improvements benefit both scripts
- Consistent API across all upload tools

### **4. Rich Querying**
- `track_utils.py` queries and manages the tracking database
- Export capabilities for analysis
- Statistical reporting across all jobs

### **5. Future Extensibility**
- Easy to add new upload scripts that use the same tracking
- Can add new tracking features without modifying upload scripts
- Modular design allows independent evolution 