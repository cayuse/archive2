# Music Archive Utilities

This directory contains utilities for bulk importing audio files into the Music Archive Rails application.

## Shared Tracking Module

### `import_tracker.py` - Shared Tracking Module

A comprehensive SQLite-based tracking system that both upload scripts use for uniform tracking capabilities.

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

A comprehensive Python script for bulk uploading audio files through the Rails API with robust tracking, resume capabilities, and detailed error reporting.

**Features:**
- **Rails API Integration**: Uploads through Rails API endpoints
- **Comprehensive Tracking**: Uses shared SQLite tracking module
- **Resume Capability**: Can resume interrupted imports from where they left off
- **Error Reporting**: Detailed error tracking with quick summaries and verbose reports
- **Batch Processing**: Support for processing files in batches for testing
- **Graceful Shutdown**: Can be stopped gracefully with 'q' key or Ctrl+C
- **Progress Monitoring**: Real-time progress with detailed statistics

### 2. Universal Upload Script (`universal_upload.py`)

A cross-platform Python script for bulk uploading audio files with direct filesystem access, bypassing Rails for maximum speed.

**Features:**
- **Direct Filesystem Access**: Bypasses Rails API for maximum upload speed
- **Cross-platform Compatibility**: Works across Linux, Mac, Windows
- **Full Unicode Support**: Handles any Unicode characters, spaces, special characters
- **Concurrent Uploads**: Configurable concurrent upload limits
- **Comprehensive Tracking**: Uses shared SQLite tracking module
- **Resume Capability**: Can resume interrupted imports
- **Error Reporting**: Detailed error tracking and recovery
- **Robust Path Handling**: Normalizes paths for any filesystem

## Usage

### Bulk Upload (Rails API)
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

### Universal Upload (Direct Filesystem)
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
- `--resume`: Resume from last successful import
- `--show-errors`: Show error summary and exit
- `--show-errors-verbose`: Show detailed error information and exit

### Processing Limits
- `--max-count N`: Maximum number of files to process
- `--continue-from N`: Continue from this offset (for batch processing)

### Tracking Options
- `--tracking-db PATH`: SQLite database for tracking progress (default: import_tracking.db)

### Authentication Options
- `--url URL`: Base URL of the archive (default: http://localhost:3000)
- `--username USERNAME`: Username/email for authentication
- `--password PASSWORD`: Password for authentication

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

The shared tracking module enables powerful workflows:

### Mixed Upload Strategies
```bash
# Start with fast direct upload
python3 universal_upload.py ~/Music --max-count 1000 --concurrent 10

# Switch to Rails API for problematic files
python3 bulk_upload.py ~/Music --resume --show-errors-verbose
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

## Performance Comparison

### Bulk Upload (`bulk_upload.py`)
- **Speed**: Slower (HTTP uploads through Rails)
- **Reliability**: High (Rails handles all processing)
- **Use Case**: When you want Rails to handle metadata extraction and processing
- **Best For**: Smaller batches, when you need Rails processing

### Universal Upload (`universal_upload.py`)
- **Speed**: Much faster (direct filesystem access)
- **Reliability**: High (bypasses Rails bottlenecks)
- **Use Case**: Large bulk imports where speed is critical
- **Best For**: 65k+ file imports, when you want maximum speed

## Tag Extractor Scripts

### Standalone Tag Extractor (`standalone_tag_extractor.rb`)

A comprehensive Ruby script for extracting metadata from audio files using both `wahwah` and `ffprobe`.

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

## Upload Method Comparison

See `UPLOAD_METHODS_COMPARISON.md` for detailed comparison of different upload approaches and their performance characteristics.

## API Documentation

See `API_DOCUMENTATION.md` for Rails API endpoint documentation.

## Test Scripts

- `test_api.sh`: Test API endpoints

## Requirements

- Python 3.6+
- Ruby 2.7+ (for tag extractors)
- ffmpeg/ffprobe (for comprehensive metadata extraction)
- Rails 8 application running

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

## Choosing the Right Script

### Use `bulk_upload.py` when:
- You want Rails to handle all metadata extraction
- You need Rails processing and validation
- You're doing smaller batches
- You want maximum reliability over speed

### Use `universal_upload.py` when:
- You need maximum upload speed
- You're doing large bulk imports (65k+ files)
- You want to bypass Rails bottlenecks
- You're doing the initial bulk import

For your 65k file import, I recommend starting with `universal_upload.py` for speed, then using `bulk_upload.py` for any files that need Rails processing.

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
- `track_utils.py` provides comprehensive database management
- Export capabilities for analysis
- Statistical reporting across all jobs

### **5. Future Extensibility**
- Easy to add new upload scripts that use the same tracking
- Can add new tracking features without modifying upload scripts
- Modular design allows independent evolution 