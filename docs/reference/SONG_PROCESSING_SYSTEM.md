# Song Processing System

## Overview

The music archive now includes a comprehensive song processing system that handles audio file uploads, metadata extraction, and maintenance workflows. This system supports both interactive web uploads and bulk API imports.

## 🎵 **Processing Statuses**

Songs can have the following processing statuses:

- **`new`** - Recently imported, needs metadata review
- **`pending`** - Queued for processing
- **`processing`** - Currently being processed
- **`completed`** - Successfully processed with complete metadata
- **`failed`** - Processing failed with error details
- **`needs_review`** - Has partial metadata, needs manual review

## 🔄 **Upload Workflows**

### **Web UI Upload Flow**

1. **Upload Page** (`/songs/upload`)
   - User selects audio file
   - Optional: pre-select album/genre
   - File validation (format, size)

2. **Processing**
   - Background job extracts metadata
   - Updates song with extracted information
   - Sets appropriate processing status

3. **Review Page** (`/songs/:id/edit`)
   - Shows extracted metadata
   - User can review and edit information
   - Form pre-filled with extracted data
   - Save to complete the process

### **API Bulk Upload Flow**

1. **Bulk Upload** (`POST /api/v1/songs/bulk`)
   - Non-interactive processing
   - Multiple songs processed in background
   - Status determined by metadata completeness:
     - Complete metadata → `completed`
     - Partial metadata → `needs_review`
     - No metadata → `new`

2. **Background Processing**
   - AudioFileProcessingJob handles metadata extraction
   - Updates song records with extracted information
   - Sets processing status based on results

## 🛠️ **Maintenance Interface**

### **Access**
- Available to moderators and admins
- Navigation: "Maintenance" in main menu

### **Features**

1. **Status Filtering**
   - Filter by processing status
   - Quick statistics dashboard
   - Focus on songs needing attention

2. **Bulk Operations**
   - Select multiple songs
   - Bulk update status, genre, album
   - Mass processing capabilities

3. **Individual Actions**
   - Edit song metadata
   - Retry failed processing
   - View processing errors

### **Maintenance Workflow**

1. **Review New Imports**
   - Songs with `new` status
   - Add missing metadata manually
   - Mark as `completed` when done

2. **Fix Failed Songs**
   - Songs with `failed` status
   - Review error messages
   - Retry processing or fix manually

3. **Review Partial Metadata**
   - Songs with `needs_review` status
   - Complete missing information
   - Verify extracted data accuracy

## 📊 **Metadata Extraction**

### **Supported Formats**
- MP3 (ID3 tags)
- M4A/MP4 (iTunes metadata)
- OGG (Vorbis comments)
- FLAC (metadata blocks)
- WAV (limited metadata)
- AAC (iTunes metadata)

### **Extracted Information**
- **Basic**: title, track_number, duration
- **File**: format, size, bitrate
- **Artist**: name (creates/finds artist record)
- **Album**: title, release_date (creates/finds album record)
- **Genre**: name (creates/finds genre record)

### **Fallback Processing**
- If no metadata tags found, parses filename
- Extracts artist/album/title from filename patterns
- Sets status to `needs_review` for manual verification

## 🔧 **Technical Implementation**

### **Models**

#### **Song Model**
```ruby
# Processing status methods
def processing_pending?
def processing_in_progress?
def processing_completed?
def processing_failed?
def needs_review?
def new_import?

# Metadata completeness
def has_complete_metadata?
def has_partial_metadata?
def has_no_metadata?

# Metadata extraction
def extract_metadata_from_file
```

#### **Scopes**
```ruby
scope :pending_processing
scope :processing
scope :completed
scope :failed
scope :needs_review
scope :new_imports
scope :needs_attention
```

### **Controllers**

#### **SongsController**
- `upload` - Upload form
- `process_upload` - Handle file upload
- `edit` - Review extracted metadata
- `maintenance` - Admin maintenance interface
- `bulk_update` - Bulk operations

#### **API Controllers**
- Automatic status assignment based on metadata
- Background processing for bulk uploads
- Error handling and status updates

### **Background Jobs**

#### **AudioFileProcessingJob**
- Processes audio files asynchronously
- Extracts metadata using AudioFileProcessor
- Updates song records with results
- Sets appropriate processing status
- Handles errors gracefully

### **Views**

#### **Upload Flow**
- `upload.html.erb` - File upload form
- `edit.html.erb` - Metadata review/edit
- `show.html.erb` - Song details with status

#### **Maintenance**
- `maintenance.html.erb` - Admin interface
- Bulk selection and operations
- Status filtering and statistics

## 🚀 **Usage Examples**

### **Web Upload**
```bash
# 1. Navigate to upload page
GET /songs/upload

# 2. Select file and upload
POST /songs/process_upload

# 3. Review extracted metadata
GET /songs/:id/edit

# 4. Save with corrections
PATCH /songs/:id
```

### **API Bulk Upload**
```bash
# Upload multiple songs
POST /api/v1/songs/bulk
Content-Type: application/json

{
  "songs": [
    {
      "title": "Song Title",
      "artist_name": "Artist Name",
      "album_title": "Album Title",
      "genre_name": "Rock"
    }
  ]
}
```

### **Maintenance**
```bash
# View songs needing attention
GET /songs/maintenance?status=needs_attention

# Bulk update status
POST /songs/bulk_update
{
  "song_ids": [1, 2, 3],
  "updates": {
    "processing_status": "completed"
  }
}
```

## 🔒 **Permissions**

### **Upload Permissions**
- **Moderators/Admins**: Can upload songs
- **Users**: Can view songs only

### **Maintenance Permissions**
- **Moderators/Admins**: Full maintenance access
- **Users**: No maintenance access

### **API Permissions**
- **API Key Required**: For bulk operations
- **Rate Limiting**: Applied to prevent abuse

## 📈 **Monitoring & Analytics**

### **Statistics Dashboard**
- Songs by processing status
- Metadata completeness rates
- Processing success/failure rates
- Recent activity metrics

### **Error Tracking**
- Failed processing logs
- Error message storage
- Retry mechanism for failed jobs

## 🔄 **Future Enhancements**

### **Planned Features**
- Real-time processing status updates (WebSocket)
- Advanced metadata extraction (lyrics, artwork)
- Batch processing improvements
- Integration with external metadata APIs
- Audio fingerprinting for duplicate detection

### **Performance Optimizations**
- Parallel processing for bulk uploads
- Caching for frequently accessed metadata
- Database indexing for status queries
- File compression for storage efficiency 