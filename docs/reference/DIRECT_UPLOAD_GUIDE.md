# Direct Upload Guide for Music Archive

## Overview

This guide explains the direct upload system designed for bulk uploads of large numbers of audio files (like your 65,000 file scenario). The system uses Active Storage's direct upload feature to bypass the Rails server and upload files directly to storage.

## 🚀 Why Direct Uploads?

### Traditional Upload Problems
- **Server Overload**: 65,000 files through Rails server = memory/CPU overload
- **Timeout Issues**: Large files can timeout during upload
- **Single Point of Failure**: If Rails server goes down, uploads fail
- **Slow Performance**: Files queue up waiting for server processing

### Direct Upload Benefits
- **Bypasses Rails Server**: Files go directly to storage (S3, GCS, local disk)
- **Parallel Processing**: Multiple files upload simultaneously
- **Resumable Uploads**: Can resume interrupted uploads
- **Better Reliability**: No server timeout issues
- **Progress Tracking**: Real-time upload progress
- **Scalable**: Can handle thousands of concurrent uploads

## 📁 File Structure

```
utilities/
├── bulk_upload.py          # Original bulk upload script (kept for reference)
├── direct_upload.py        # NEW: Direct upload script for bulk operations
└── requirements.txt        # Python dependencies for direct upload

archive/
├── app/controllers/api/v1/songs_controller.rb  # Updated with direct upload endpoints
└── config/routes.rb       # Updated with new routes
```

## 🔧 Setup Instructions

### 1. Install Python Dependencies

```bash
cd utilities
pip install -r requirements.txt
```

### 2. Configure Rails for Direct Uploads

The Rails application is already configured with Active Storage. The new endpoints are:

- `POST /api/v1/songs/direct_upload` - Get direct upload URL
- `POST /api/v1/songs/create_from_blob` - Create song from uploaded blob

### 3. Test the System

```bash
# Test with a small directory first
python3 utilities/direct_upload.py ~/test_music --dry-run --verbose

# Then run the real upload
python3 utilities/direct_upload.py ~/your_music_collection --verbose --concurrent 10
```

## 📊 Usage Comparison

### Original Bulk Upload (`bulk_upload.py`)
```bash
# Uploads through Rails server
python3 utilities/bulk_upload.py ~/Music --verbose
```

**Flow:**
1. File → Rails Server → Storage
2. Rails processes file in memory
3. Server can become overloaded with many files

### New Direct Upload (`direct_upload.py`)
```bash
# Uploads directly to storage
python3 utilities/direct_upload.py ~/Music --verbose --concurrent 10
```

**Flow:**
1. Get direct upload URL from Rails
2. File → Storage (bypassing Rails)
3. Create song record with blob reference
4. Rails processes metadata separately

## 🎯 Performance Comparison

| Metric | Traditional Upload | Direct Upload |
|--------|-------------------|---------------|
| **Server Load** | High (processes files) | Low (metadata only) |
| **Concurrent Uploads** | 1-2 files | 10-50 files |
| **Memory Usage** | High (file in memory) | Low (streaming) |
| **Timeout Risk** | High | Low |
| **Resumable** | No | Yes |
| **Progress Tracking** | Basic | Real-time |

## 📝 Usage Examples

### Basic Upload
```bash
python3 utilities/direct_upload.py ~/Music --username admin@musicarchive.com --password mypass
```

### Verbose Upload with Progress
```bash
python3 utilities/direct_upload.py ~/Music \
  --username admin@musicarchive.com \
  --password mypass \
  --verbose \
  --concurrent 15
```

### Dry Run (Test Only)
```bash
python3 utilities/direct_upload.py ~/Music --dry-run --verbose
```

### High-Performance Upload
```bash
python3 utilities/direct_upload.py ~/Music \
  --username admin@musicarchive.com \
  --password mypass \
  --concurrent 20 \
  --url https://myarchive.com
```

## 🔄 Upload Process

### Step 1: Authentication
```python
# Script authenticates with Rails API
response = requests.post("/api/v1/auth/login", json={
    "email": username,
    "password": password
})
api_token = response.json()["api_token"]
```

### Step 2: Get Direct Upload URL
```python
# Get direct upload URL from Rails
response = requests.post("/api/v1/songs/direct_upload", json={
    "filename": "song.mp3",
    "content_type": "audio/mpeg",
    "byte_size": 1234567
})
direct_upload_data = response.json()["direct_upload"]
```

### Step 3: Upload File Directly to Storage
```python
# Upload file directly to storage (bypassing Rails)
async with aiohttp.ClientSession() as session:
    async with session.put(
        direct_upload_data["url"],
        data=file_data,
        headers=direct_upload_data["headers"]
    ) as response:
        # File uploaded to storage
```

### Step 4: Create Song Record
```python
# Create song record with blob reference
response = requests.post("/api/v1/songs/create_from_blob", json={
    "blob_signed_id": direct_upload_data["signed_id"],
    "filename": "song.mp3",
    "metadata": {"title": "Song Title"}
})
```

## ⚙️ Configuration Options

### Concurrent Uploads
```bash
--concurrent 5    # Default: 5 concurrent uploads
--concurrent 10   # Medium: 10 concurrent uploads
--concurrent 20   # High: 20 concurrent uploads
```

### Verbose Output
```bash
--verbose         # Show detailed progress for each file
```

### Dry Run
```bash
--dry-run         # Test without actually uploading
```

### Custom Server
```bash
--url https://myarchive.com  # Custom server URL
```

## 🛠️ Troubleshooting

### Common Issues

#### 1. Authentication Failed
```bash
# Check credentials
python3 utilities/direct_upload.py ~/Music --username admin@musicarchive.com --password mypass
```

#### 2. Network Timeout
```bash
# Reduce concurrent uploads
python3 utilities/direct_upload.py ~/Music --concurrent 3
```

#### 3. Storage Permission Issues
```bash
# Check Rails logs
tail -f archive/log/development.log
```

#### 4. Memory Issues
```bash
# Reduce concurrent uploads and use smaller files first
python3 utilities/direct_upload.py ~/Music --concurrent 2
```

### Debug Mode
```bash
# Run with maximum verbosity
python3 utilities/direct_upload.py ~/Music --verbose --concurrent 1
```

## 📈 Monitoring Upload Progress

### Real-time Monitoring
```bash
# Watch Rails logs
tail -f archive/log/development.log | grep "Direct upload"

# Watch database
bin/rails console
Song.where(processing_status: 'needs_review').count
```

### Progress Tracking
The script shows:
- Files found
- Upload progress
- Success/failure counts
- Individual file status (with --verbose)

## 🔒 Security Considerations

### API Authentication
- Bearer token authentication required
- Tokens expire after 1 hour
- Moderator/admin permissions required

### File Validation
- File type validation on Rails side
- File size limits configurable
- Content-type verification

### Storage Security
- Direct upload URLs are temporary
- Signed IDs prevent tampering
- Blob records are secure

## 🚀 Production Deployment

### For 65,000 Files

1. **Start Small**: Test with 100 files first
2. **Monitor Resources**: Watch server CPU/memory
3. **Adjust Concurrency**: Start with 5, increase to 10-20
4. **Use Dry Run**: Test the process first
5. **Monitor Progress**: Check logs and database

### Recommended Commands

```bash
# Test run
python3 utilities/direct_upload.py ~/Music --dry-run --verbose

# Small batch test
python3 utilities/direct_upload.py ~/Music/small_batch --verbose --concurrent 5

# Full upload
python3 utilities/direct_upload.py ~/Music --verbose --concurrent 10
```

## 📊 Expected Performance

### For 65,000 Files (Average 5MB each)

| Concurrency | Estimated Time | Server Load |
|-------------|----------------|-------------|
| 5 uploads   | ~18 hours      | Low        |
| 10 uploads  | ~9 hours       | Medium      |
| 20 uploads  | ~4.5 hours     | High        |

### Factors Affecting Speed
- **File Size**: Larger files = longer uploads
- **Network Speed**: Upload bandwidth
- **Storage Type**: S3 vs local disk
- **Server Resources**: CPU/memory available

## 🔄 Migration Strategy

### Phase 1: Keep Both Systems
- Use direct upload for bulk operations
- Keep traditional upload for individual files
- Both systems functional simultaneously

### Phase 2: Evaluate Performance
- Monitor upload success rates
- Compare processing times
- Gather user feedback

### Phase 3: Optimize
- Adjust concurrency settings
- Fine-tune server configuration
- Optimize storage settings

## 📞 Support

### Getting Help
1. Check Rails logs: `tail -f archive/log/development.log`
2. Test with dry run: `--dry-run --verbose`
3. Reduce concurrency if having issues
4. Check network connectivity

### Common Commands
```bash
# Check upload status
bin/rails console
Song.where(processing_status: 'needs_review').count

# Monitor background jobs
bin/rails console
Sidekiq::Queue.new.size

# Check storage
ls -la archive/storage/
```

This direct upload system should handle your 65,000 file upload much more efficiently than the traditional approach! 