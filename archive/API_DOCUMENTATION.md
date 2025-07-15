# Music Archive API Documentation

## Overview

The Music Archive API provides comprehensive access to the music library for bulk operations, external applications, and music player integration. The API supports both individual operations and bulk operations for managing thousands of songs efficiently.

## 🔐 Authentication

### API Token Authentication
All API endpoints require authentication using Bearer tokens.

```bash
# Login to get a token
curl -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "admin@musicarchive.com", "password": "admin123"}'

# Use token in subsequent requests
curl -H "Authorization: Bearer YOUR_TOKEN" \
  http://localhost:3000/api/v1/songs
```

### Response Format
```json
{
  "success": true,
  "token": "abc123...",
  "user": {
    "id": 1,
    "email": "admin@musicarchive.com",
    "name": "Admin User",
    "role": "admin"
  }
}
```

## 📊 Bulk Operations

### Bulk Song Creation
Import thousands of songs efficiently using JSON or CSV formats.

```bash
# JSON bulk creation
curl -X POST http://localhost:3000/api/v1/songs/bulk_create \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "songs": [
      {
        "title": "Song Title",
        "track_number": 1,
        "duration": 180,
        "file_format": "mp3",
        "file_size": 5242880,
        "artist_name": "Artist Name",
        "album_title": "Album Title",
        "album_release_date": "2023-01-01",
        "genre_name": "Rock"
      }
    ]
  }'
```

### CSV Import
Upload CSV files for bulk import:

```bash
curl -X POST http://localhost:3000/api/v1/songs/bulk_upload \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -F "file=@songs.csv"
```

**CSV Format:**
```csv
title,track_number,duration,file_format,file_size,artist_name,album_title,album_release_date,genre_name
"Song Title",1,180,mp3,5242880,"Artist Name","Album Title","2023-01-01","Rock"
```

### Bulk Update
Update multiple songs at once:

```bash
curl -X PUT http://localhost:3000/api/v1/songs/bulk_update \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "songs": [
      {
        "id": 1,
        "title": "Updated Title",
        "duration": 200
      }
    ]
  }'
```

### Bulk Delete
Remove multiple songs:

```bash
curl -X DELETE http://localhost:3000/api/v1/songs/bulk_destroy \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"song_ids": [1, 2, 3]}'
```

## 🎵 Song Management

### List Songs
```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
  "http://localhost:3000/api/v1/songs?page=1&per_page=50"
```

**Response:**
```json
{
  "songs": [
    {
      "id": 1,
      "title": "Song Title",
      "track_number": 1,
      "duration": 180,
      "file_format": "mp3",
      "file_size": 5242880,
      "created_at": "2023-01-01T00:00:00Z",
      "updated_at": "2023-01-01T00:00:00Z",
      "artist": {
        "id": 1,
        "name": "Artist Name"
      },
      "album": {
        "id": 1,
        "title": "Album Title",
        "release_date": "2023-01-01"
      },
      "genre": {
        "id": 1,
        "name": "Rock",
        "color": "#FF0000"
      },
      "audio_file_url": "http://localhost:3000/rails/active_storage/blobs/...",
      "stream_url": "http://localhost:3000/api/v1/audio_files/1/stream"
    }
  ],
  "pagination": {
    "current_page": 1,
    "total_pages": 10,
    "total_count": 500
  }
}
```

### Get Single Song
```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
  http://localhost:3000/api/v1/songs/1
```

### Export Songs
```bash
# JSON export
curl -H "Authorization: Bearer YOUR_TOKEN" \
  "http://localhost:3000/api/v1/songs/export?format=json"

# CSV export
curl -H "Authorization: Bearer YOUR_TOKEN" \
  "http://localhost:3000/api/v1/songs/export?format=csv" \
  -o songs_export.csv
```

## 🎧 Audio Streaming

### Stream Audio File
```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
  "http://localhost:3000/api/v1/audio_files/1/stream" \
  -o song.mp3
```

**Features:**
- Range requests supported for seeking
- Proper content-type headers
- Chunked streaming for large files

### Download Audio File
```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
  "http://localhost:3000/api/v1/audio_files/1/download" \
  -o "Artist - Song.mp3"
```

## 🎼 Playlist Management

### List Playlists
```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
  "http://localhost:3000/api/v1/playlists?page=1&per_page=20"
```

### Get Playlist with Songs
```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
  http://localhost:3000/api/v1/playlists/1
```

### Add Song to Playlist
```bash
curl -X POST http://localhost:3000/api/v1/playlists/1/add_song \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"song_id": 1, "position": 5}'
```

### Remove Song from Playlist
```bash
curl -X DELETE http://localhost:3000/api/v1/playlists/1/remove_song \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"song_id": 1}'
```

### Reorder Playlist Songs
```bash
curl -X PUT http://localhost:3000/api/v1/playlists/1/reorder_songs \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"song_order": [3, 1, 2, 4]}'
```

## 🔍 Search API

### Search Songs
```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
  "http://localhost:3000/api/v1/search?q=rock&type=songs&page=1&per_page=20"
```

### Search Artists
```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
  "http://localhost:3000/api/v1/search?q=beatles&type=artists"
```

### Search Genres
```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
  "http://localhost:3000/api/v1/search?q=rock&type=genres"
```

### Search All Types
```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
  "http://localhost:3000/api/v1/search?q=rock&type=all"
```

### Get Search Suggestions
```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
  "http://localhost:3000/api/v1/search/suggestions?q=rock"
```

**Response:**
```json
[
  {
    "type": "song",
    "text": "Rock Song",
    "id": 1,
    "artist": "Artist Name",
    "album": "Album Title"
  },
  {
    "type": "artist",
    "text": "Rock Band",
    "id": 2,
    "country": "USA"
  },
  {
    "type": "genre",
    "text": "Rock",
    "id": 3,
    "color": "#FF0000"
  }
]
```

## 🏥 Health Check

### API Health Status
```bash
curl http://localhost:3000/api/v1/health
```

**Response:**
```json
{
  "status": "healthy",
  "timestamp": "2023-01-01T00:00:00Z",
  "checks": {
    "database": true,
    "storage": true,
    "search": true
  },
  "version": "1.0.0"
}
```

## 🎵 Music Player Integration

### Example: JavaScript Music Player
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
  
  async streamSong(songId) {
    const response = await fetch(
      `${this.baseUrl}/audio_files/${songId}/stream`,
      {
        headers: {
          'Authorization': `Bearer ${this.apiToken}`
        }
      }
    );
    return response.blob();
  }
}

// Usage
const player = new MusicPlayer('your-api-token');
const songs = await player.searchSongs('rock');
const playlist = await player.getPlaylist(1);
const audioBlob = await player.streamSong(1);
```

## 📊 Bulk Import Examples

### Python Script for Bulk Import
```python
import requests
import json

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

# Bulk create from JSON
songs = [
    {
        "title": "Song 1",
        "artist_name": "Artist 1",
        "album_title": "Album 1",
        "genre_name": "Rock",
        "track_number": 1,
        "duration": 180
    }
]
result = api.bulk_create_songs(songs)

# Upload CSV file
result = api.upload_csv("songs.csv")
```

## 🔧 Error Handling

### Common Error Responses
```json
{
  "success": false,
  "error": "Error message"
}
```

### HTTP Status Codes
- `200` - Success
- `400` - Bad Request (invalid parameters)
- `401` - Unauthorized (invalid/missing token)
- `403` - Forbidden (insufficient permissions)
- `404` - Not Found
- `422` - Unprocessable Entity (validation errors)
- `500` - Internal Server Error

### Rate Limiting
- API requests are limited to 1000 requests per hour per user
- Bulk operations are limited to 10 operations per minute
- File uploads are limited to 100MB per request

## 🚀 Performance Tips

### For Bulk Operations
1. Use CSV uploads for large datasets (>1000 songs)
2. Batch operations in groups of 100-500 songs
3. Use background jobs for very large imports
4. Monitor memory usage during bulk operations

### For Music Player Integration
1. Use range requests for audio streaming
2. Cache playlist data on the client side
3. Implement pagination for large result sets
4. Use search suggestions for better UX

### For Search Operations
1. Use specific search types (songs, artists, genres) when possible
2. Implement client-side caching for repeated searches
3. Use pagination to limit result sets
4. Consider implementing search result caching

## 🔒 Security Considerations

1. **Token Security**: Store tokens securely, rotate regularly
2. **Rate Limiting**: Implement client-side rate limiting
3. **Input Validation**: Validate all input data
4. **File Uploads**: Scan uploaded files for malware
5. **CORS**: Configure CORS for web applications
6. **HTTPS**: Use HTTPS in production

## 📝 API Versioning

The API uses URL versioning (`/api/v1/`). Future versions will be available at `/api/v2/`, etc.

## 🆘 Support

For API support and questions:
- Check the health endpoint for system status
- Review error responses for debugging
- Monitor rate limiting headers
- Use the search suggestions for better UX 