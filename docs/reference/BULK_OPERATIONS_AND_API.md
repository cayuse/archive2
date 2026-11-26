# Bulk Operations & API System

## Overview

The Music Archive now supports comprehensive bulk operations and API access for managing thousands of songs efficiently. This system provides both web-based interfaces and programmatic access for external applications and music players.

## 🚀 Key Features

### 1. **Bulk Song Import**
- **CSV Upload**: Import thousands of songs via CSV files
- **JSON API**: Programmatic bulk creation via API
- **Auto-Association**: Automatically creates/finds artists, albums, and genres
- **Error Handling**: Detailed error reporting for failed imports

### 2. **API Access**
- **RESTful API**: Complete API for external applications
- **Token Authentication**: Secure Bearer token authentication
- **Audio Streaming**: Range-request supported audio streaming
- **Search API**: Full-text search with pagination

### 3. **Music Player Integration**
- **Playlist Management**: Add/remove/reorder songs in playlists
- **Audio Streaming**: HTTP range requests for seeking
- **Search Integration**: Real-time search with suggestions

## 📊 Bulk Operations

### Web Interface
Access via: `/bulk_operations` (moderator/admin only)

**Features:**
- CSV file upload with validation
- Export all songs to CSV
- Bulk delete by song IDs
- Library statistics dashboard
- Recent songs table

### CSV Import Format
```csv
title,track_number,duration,file_format,file_size,artist_name,album_title,album_release_date,genre_name
"Song Title",1,180,mp3,5242880,"Artist Name","Album Title","2023-01-01","Rock"
```

### API Bulk Operations
```bash
# Bulk create songs
curl -X POST http://localhost:3000/api/v1/songs/bulk_create \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"songs": [{"title": "Song", "artist_name": "Artist", ...}]}'

# Upload CSV file
curl -X POST http://localhost:3000/api/v1/songs/bulk_upload \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -F "file=@songs.csv"

# Export songs
curl -H "Authorization: Bearer YOUR_TOKEN" \
  "http://localhost:3000/api/v1/songs/export?format=csv" \
  -o songs_export.csv
```

## 🎵 API Endpoints

### Authentication
```bash
# Login
POST /api/v1/auth/login
# Logout
POST /api/v1/auth/logout
```

### Songs
```bash
# List songs (paginated)
GET /api/v1/songs?page=1&per_page=50

# Get single song
GET /api/v1/songs/:id

# Bulk operations
POST /api/v1/songs/bulk_create
PUT /api/v1/songs/bulk_update
DELETE /api/v1/songs/bulk_destroy
POST /api/v1/songs/bulk_upload
GET /api/v1/songs/export
```

### Audio Files
```bash
# Stream audio (with range requests)
GET /api/v1/audio_files/:id/stream

# Download audio
GET /api/v1/audio_files/:id/download
```

### Playlists
```bash
# List playlists
GET /api/v1/playlists

# Get playlist with songs
GET /api/v1/playlists/:id

# Playlist management
POST /api/v1/playlists/:id/add_song
DELETE /api/v1/playlists/:id/remove_song
PUT /api/v1/playlists/:id/reorder_songs
```

### Search
```bash
# Search all types
GET /api/v1/search?q=rock&type=all

# Search specific types
GET /api/v1/search?q=rock&type=songs
GET /api/v1/search?q=beatles&type=artists
GET /api/v1/search?q=rock&type=genres

# Search suggestions
GET /api/v1/search/suggestions?q=rock
```

### Health Check
```bash
# System health
GET /api/v1/health
```

## 🎧 Music Player Integration

### JavaScript Example
```javascript
class MusicPlayer {
  constructor(apiToken) {
    this.apiToken = apiToken;
    this.baseUrl = 'http://localhost:3000/api/v1';
  }
  
  async searchSongs(query) {
    const response = await fetch(
      `${this.baseUrl}/search?q=${encodeURIComponent(query)}&type=songs`,
      {
        headers: {
          'Authorization': `Bearer ${this.apiToken}`
        }
      }
    );
    return response.json();
  }
  
  async streamSong(songId, startByte = 0) {
    const response = await fetch(
      `${this.baseUrl}/audio_files/${songId}/stream`,
      {
        headers: {
          'Authorization': `Bearer ${this.apiToken}`,
          'Range': `bytes=${startByte}-`
        }
      }
    );
    return response.blob();
  }
  
  async getPlaylist(playlistId) {
    const response = await fetch(
      `${this.baseUrl}/playlists/${playlistId}`,
      {
        headers: {
          'Authorization': `Bearer ${this.apiToken}`
        }
      }
    );
    return response.json();
  }
}
```

### Python Integration Example
```python
import requests

class MusicArchiveAPI:
    def __init__(self, base_url, email, password):
        self.base_url = base_url
        self.token = self.login(email, password)
    
    def login(self, email, password):
        response = requests.post(f"{self.base_url}/api/v1/auth/login", json={
            "email": email,
            "password": password
        })
        return response.json()["token"]
    
    def bulk_create_songs(self, songs_data):
        headers = {"Authorization": f"Bearer {self.token}"}
        response = requests.post(
            f"{self.base_url}/api/v1/songs/bulk_create",
            headers=headers,
            json={"songs": songs_data}
        )
        return response.json()
    
    def upload_csv(self, csv_file_path):
        headers = {"Authorization": f"Bearer {self.token}"}
        with open(csv_file_path, 'rb') as f:
            files = {"file": f}
            response = requests.post(
                f"{self.base_url}/api/v1/songs/bulk_upload",
                headers=headers,
                files=files
            )
        return response.json()

# Usage
api = MusicArchiveAPI("http://localhost:3000", "admin@musicarchive.com", "admin123")
result = api.upload_csv("songs.csv")
```

## 🔧 Performance Optimizations

### For Bulk Operations
1. **Batch Processing**: Process songs in batches of 100-500
2. **Database Transactions**: Wrap bulk operations in transactions
3. **Background Jobs**: Use background jobs for very large imports
4. **Memory Management**: Stream large files to avoid memory issues

### For API Access
1. **Pagination**: All list endpoints support pagination
2. **Eager Loading**: Includes associations to reduce N+1 queries
3. **Caching**: Consider implementing response caching
4. **Rate Limiting**: Implement client-side rate limiting

### For Audio Streaming
1. **Range Requests**: Support HTTP range requests for seeking
2. **Chunked Streaming**: Stream files in chunks to avoid memory issues
3. **Content-Type Headers**: Proper MIME type detection
4. **File Size Limits**: Configure appropriate file size limits

## 🔒 Security Features

### Authentication
- Bearer token authentication for all API endpoints
- Token-based session management
- Role-based access control (user, moderator, admin)

### Authorization
- Moderator/admin required for bulk operations
- User-specific playlist access
- Public/private playlist support

### Input Validation
- CSV format validation
- File type validation
- Data sanitization
- SQL injection prevention

## 📈 Scalability Considerations

### Database
- PostgreSQL full-text search with GIN indexes
- Proper foreign key constraints
- Database connection pooling
- Query optimization

### Storage
- Active Storage for file management
- Configurable storage backends (local, S3, etc.)
- File format validation
- Virus scanning (recommended)

### API
- RESTful design principles
- Consistent error handling
- Versioned API endpoints
- Comprehensive documentation

## 🚀 Usage Scenarios

### 1. **Large Music Library Import**
```bash
# Prepare CSV file with thousands of songs
# Upload via web interface or API
# Monitor progress and handle errors
# Verify import results
```

### 2. **External Music Player**
```javascript
// Player connects to API
// Searches for songs
// Streams audio with seeking support
// Manages playlists
// Handles authentication
```

### 3. **Backup and Migration**
```bash
# Export all songs to CSV
# Import to new system
# Verify data integrity
# Handle missing files
```

### 4. **Bulk Metadata Updates**
```bash
# Export current data
# Update in spreadsheet
# Import updated data
# Verify changes
```

## 🔧 Configuration

### Environment Variables
```bash
# Database
DATABASE_URL=postgresql://user:pass@localhost/music_archive

# Storage
ACTIVE_STORAGE_SERVICE=local  # or s3, gcs, etc.

# API Settings
API_RATE_LIMIT=1000  # requests per hour
MAX_FILE_SIZE=100MB
```

### Production Considerations
1. **HTTPS**: Use HTTPS for all API communication
2. **CORS**: Configure CORS for web applications
3. **Rate Limiting**: Implement server-side rate limiting
4. **Monitoring**: Add API usage monitoring
5. **Backup**: Regular database and file backups

## 📚 Documentation

- **API Documentation**: `API_DOCUMENTATION.md`
- **Usage Notes**: `USAGENOTES.txt`
- **Authorization**: `PUNDIT_AUTHORIZATION.md`

## 🆘 Troubleshooting

### Common Issues
1. **CSV Import Errors**: Check CSV format and required columns
2. **Authentication Errors**: Verify token and user permissions
3. **File Upload Issues**: Check file size and format limits
4. **Performance Issues**: Monitor database and storage usage

### Debug Commands
```bash
# Check API health
curl http://localhost:3000/api/v1/health

# Test authentication
curl -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "admin@musicarchive.com", "password": "admin123"}'

# View API routes
rails routes | grep api
```

This comprehensive system provides everything needed to manage thousands of songs efficiently while supporting external applications and music players. 