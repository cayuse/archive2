# Music Archive Utilities

This directory contains utility scripts for interacting with the Music Archive API.

## Bulk Upload Script

The `bulk_upload.py` script is a core component for adding large amounts of music to the archive. It supports flexible metadata handling and can extract information from filenames.

### Features

- **Flexible URL Configuration**: Connect to any archive instance
- **Metadata Extraction**: Automatically extract metadata from filenames
- **Skip Processing**: Option to skip automatic metadata extraction from audio files
- **Progress Tracking**: Visual progress bar with file information
- **Dry Run Mode**: Test uploads without actually uploading
- **Verbose Output**: Detailed logging for debugging

### Usage

```bash
python3 bulk_upload.py <directory_path> [options]
```

### Arguments

- `directory_path`: Path to directory containing audio files

### Options

- `--url URL`: Base URL of the archive (default: http://localhost:3000)
- `--username USERNAME`: Username/email for authentication
- `--password PASSWORD`: Password for authentication
- `-d, --dry-run`: Show what would be uploaded without actually uploading
- `-v, --verbose`: Verbose output
- `--skip-metadata`: Skip automatic metadata extraction from audio files
- `--extract-metadata`: Extract metadata from filenames (default: enabled)
- `-h, --help`: Show help message

### Examples

#### Basic Upload
```bash
python3 bulk_upload.py ~/Music --username admin@example.com --password mypass
```

#### Upload to Remote Archive
```bash
python3 bulk_upload.py ~/Music --url https://myarchive.com --username admin@example.com --password mypass
```

#### Dry Run with Verbose Output
```bash
python3 bulk_upload.py ~/Music --username admin@example.com --password mypass --dry-run --verbose
```

#### Skip Audio Metadata Extraction
```bash
python3 bulk_upload.py ~/Music --username admin@example.com --password mypass --skip-metadata
```

### Filename Metadata Extraction

The script can extract metadata from filenames using common patterns:

#### Supported Patterns

1. **Artist - Album - Track - Title**
   ```
   Artist Name - Album Title - 01 - Song Title.mp3
   ```

2. **Artist - Album - Title**
   ```
   Artist Name - Album Title - Song Title.mp3
   ```

3. **Artist - Title**
   ```
   Artist Name - Song Title.mp3
   ```

4. **Just Title**
   ```
   Song Title.mp3
   ```

#### Metadata Mapping

- `artist_name`: Artist name
- `album_title`: Album title
- `track_number`: Track number (if present)
- `title`: Song title

### Processing Options

#### Metadata Extraction from Filenames
- **Enabled by default**: The script automatically extracts metadata from filenames
- **Disable**: Use `--no-extract-metadata` to disable this feature

#### Audio File Metadata Extraction
- **Enabled by default**: The Rails API extracts metadata from audio file tags
- **Skip**: Use `--skip-metadata` to skip this processing step

#### Processing Status

The API sets processing status based on provided metadata:

- **`completed`**: All metadata provided (artist, album, genre)
- **`needs_review`**: Partial metadata provided
- **`processing`**: No metadata provided, will extract from file
- **`new`**: Skip metadata extraction, minimal processing

### Authentication

The script supports two authentication methods:

1. **Command line arguments**:
   ```bash
   python3 bulk_upload.py ~/Music --username admin@example.com --password mypass
   ```

2. **Interactive prompts**:
   ```bash
   python3 bulk_upload.py ~/Music
   # Username/Email: admin@example.com
   # Password: ********
   ```

### Error Handling

The script handles various error conditions:

- **Network errors**: Retry logic and clear error messages
- **Authentication failures**: Clear feedback on credential issues
- **File access errors**: Graceful handling of permission issues
- **API errors**: Detailed error messages from the server

### Dependencies

```bash
pip install requests tqdm
```

### Testing

Use the test script to verify functionality:

```bash
python3 test_bulk_upload.py
```

This will create test files and run dry-run tests to verify the upload process.

## API Integration

The bulk upload script integrates with the Music Archive API:

### Endpoints Used

- `POST /api/v1/auth/login`: Authentication
- `POST /api/v1/songs/bulk_upload`: File upload with metadata

### API Features

- **Flexible Metadata**: Send any combination of metadata parameters
- **Processing Control**: Skip or enable metadata extraction
- **Status Tracking**: Monitor processing status of uploaded songs
- **Error Recovery**: Graceful handling of upload failures

### Response Format

```json
{
  "success": true,
  "message": "Song uploaded successfully",
  "song": {
    "id": 123,
    "title": "Song Title",
    "processing_status": "completed",
    "created_at": "2025-07-15T14:30:00Z"
  }
}
```

## Troubleshooting

### Common Issues

1. **Authentication failed**
   - Check username and password
   - Verify the user has upload permissions

2. **Network errors**
   - Check the archive URL is correct
   - Verify network connectivity

3. **File not found**
   - Check the directory path exists
   - Verify file permissions

4. **Upload failures**
   - Check file format is supported
   - Verify file is not corrupted

### Debug Mode

Use verbose output to see detailed information:

```bash
python3 bulk_upload.py ~/Music --username admin@example.com --password mypass --verbose
```

### Dry Run Testing

Test uploads without actually uploading:

```bash
python3 bulk_upload.py ~/Music --username admin@example.com --password mypass --dry-run --verbose
```

## Future Enhancements

- **Batch processing**: Upload multiple files in parallel
- **Resume functionality**: Continue interrupted uploads
- **Metadata validation**: Verify extracted metadata accuracy
- **Progress persistence**: Save upload progress for large batches
- **Custom metadata**: Allow custom metadata field mapping 