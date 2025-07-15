# Music Archive Utilities

This folder contains utilities for bulk uploading songs to the Music Archive via API.

## Files

- `bulk_upload.sh` - Main bulk upload script
- `test_api.sh` - API testing script
- `API_DOCUMENTATION.md` - Complete API documentation

## Quick Start

### 1. Test the API

First, make sure your Rails server is running:

```bash
cd /workspaces/dockercrap/archive
bin/rails server -b 0.0.0.0 -p 3000
```

Then test the API:

```bash
cd /workspaces/dockercrap/utilities
./test_api.sh
```

### 2. Get an API Token

Use the test script to get an API token, or manually authenticate:

```bash
curl -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "admin@example.com",
    "password": "password123"
  }'
```

### 3. Upload Songs

Use the bulk upload script:

```bash
# Dry run (see what would be uploaded)
./bulk_upload.sh /path/to/music/folder -k YOUR_API_TOKEN -d

# Actually upload
./bulk_upload.sh /path/to/music/folder -k YOUR_API_TOKEN

# Verbose output
./bulk_upload.sh /path/to/music/folder -k YOUR_API_TOKEN -v
```

## Features

### Bulk Upload Script (`bulk_upload.sh`)

- **Recursive scanning**: Finds all audio files in subdirectories
- **Multiple formats**: Supports MP3, WAV, FLAC, M4A, OGG, AAC
- **Progress tracking**: Shows upload progress and file sizes
- **Error handling**: Continues on individual file failures
- **Dry run mode**: Test without actually uploading
- **Verbose output**: Detailed logging for debugging

### API Testing Script (`test_api.sh`)

- **Server check**: Verifies the Rails server is running
- **Authentication test**: Tests login and token generation
- **Endpoint testing**: Tests all major API endpoints
- **Error reporting**: Clear error messages and status codes

## Supported Audio Formats

- MP3 (.mp3)
- WAV (.wav)
- FLAC (.flac)
- M4A (.m4a)
- OGG (.ogg)
- AAC (.aac)

## How It Works

1. **Authentication**: Script authenticates with email/password to get API token
2. **File Discovery**: Recursively scans directory for audio files
3. **Upload**: Each file is uploaded via multipart/form-data
4. **Metadata Extraction**: Rails automatically extracts metadata from audio files
5. **Status Tracking**: Songs start as "processing" and update to "complete" when metadata is extracted

## Song Status Values

- `processing` - File uploaded, metadata extraction in progress
- `complete` - All metadata extracted successfully
- `needs_review` - Metadata incomplete, requires manual review
- `error` - Processing failed

## Permissions

- **Admin/Moderator**: Can upload songs and perform all bulk operations
- **Regular User**: Can only view songs (read-only access)

## Troubleshooting

### Common Issues

1. **Server not running**
   ```
   Error: Server is not running
   Solution: Start Rails server with `bin/rails server`
   ```

2. **Authentication failed**
   ```
   Error: Invalid email or password
   Solution: Check your credentials or create a user account
   ```

3. **Permission denied**
   ```
   Error: Insufficient permissions for upload
   Solution: Use an admin or moderator account
   ```

4. **File not found**
   ```
   Error: Directory does not exist
   Solution: Check the path to your music folder
   ```

### Debug Mode

Use verbose output to see detailed information:

```bash
./bulk_upload.sh /path/to/music -k YOUR_TOKEN -v
```

### Dry Run

Test what would be uploaded without actually uploading:

```bash
./bulk_upload.sh /path/to/music -k YOUR_TOKEN -d
```

## Examples

### Upload a single folder
```bash
./bulk_upload.sh ~/Music/Rock -k YOUR_API_TOKEN
```

### Upload with progress tracking
```bash
./bulk_upload.sh ~/Music -k YOUR_API_TOKEN -v
```

### Test upload without actually uploading
```bash
./bulk_upload.sh ~/Music -k YOUR_API_TOKEN -d -v
```

### Test API endpoints
```bash
./test_api.sh -e your_email@example.com -p your_password
```

## API Endpoints

- `POST /api/v1/auth/login` - Get API token
- `GET /api/v1/auth/verify` - Verify API token
- `POST /api/v1/songs/bulk_upload` - Upload single song
- `GET /api/v1/songs` - List songs
- `POST /api/v1/songs/bulk_create` - Create multiple songs
- `GET /api/v1/songs/export` - Export songs to CSV

See `API_DOCUMENTATION.md` for complete API documentation. 