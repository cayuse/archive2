# Archive API Specification

## Overview

This document defines the comprehensive API specification for the Archive music management system. The API provides programmatic access to all core functionality including authentication, music library management, playlist operations, bulk operations, and audio file streaming.

## API Design Principles

### Authentication & Authorization
- **Token-based Authentication**: All API endpoints require Bearer token authentication
- **Role-based Access Control**: Three user roles (user, moderator, admin) with different permission levels
- **Secure Token Management**: Tokens expire after 30 days and can be verified/refreshed

**Authentication Flow**:
1. Client sends credentials to `/api/v1/auth/login`
2. Server validates credentials and returns a Base64-encoded token
3. Client includes token in all subsequent requests: `Authorization: Bearer <token>`
4. Server validates token on each request and returns user context
5. Token expires after 30 days - client must re-authenticate

### Response Format
All API responses follow a consistent JSON structure:
```json
{
  "success": true|false,
  "message": "Human-readable message",
  "data": { /* response data */ },
  "errors": [ /* array of error messages */ ],
  "pagination": { /* pagination info when applicable */ }
}
```

**JSON-First Design**:
- All API endpoints return JSON by default
- CSV export is available as an optional format parameter for specific export endpoints
- Consistent field naming and data types across all endpoints
- Proper HTTP status codes with JSON error responses

### Error Handling
- **HTTP Status Codes**: Proper use of HTTP status codes (200, 201, 400, 401, 403, 404, 422, 500)
- **Validation Errors**: Detailed field-level validation errors for 422 responses
- **Rate Limiting**: Consider implementing rate limiting for production use

### Endpoint Discovery
- **Base URL**: All API endpoints are prefixed with `/api/v1/`
- **Health Check**: `/api/v1/health` provides system status and endpoint availability
- **Versioning**: API version is included in the URL path for future compatibility

## User Roles & Permissions

### User (role: 0)
- View all music content (songs, artists, albums, genres)
- Create and manage personal playlists
- View public playlists from other users
- Download/stream audio files
- Update own profile

### Moderator (role: 1)
- All user permissions
- Create, edit, and update songs, artists, albums, genres
- Upload audio files
- Access bulk operations
- Manage playlist content

### Admin (role: 2)
- All moderator permissions
- Full CRUD operations on all data
- User account management
- System configuration
- Delete any content

## Authentication Endpoints

### POST /api/v1/auth/login
**Purpose**: Authenticate user and receive API token

**Request Body**:
```json
{
  "email": "user@example.com",
  "password": "password123"
}
```

**Response** (200 OK):
```json
{
  "success": true,
  "message": "Authentication successful",
  "api_token": "base64_encoded_token",
  "user": {
    "id": 1,
    "name": "User Name",
    "email": "user@example.com",
    "role": "moderator"
  }
}
```

**Error Response** (401 Unauthorized):
```json
{
  "success": false,
  "message": "Invalid email or password"
}
```

### POST /api/v1/auth/logout
**Purpose**: Logout user (invalidate token on client side)

**Headers**: `Authorization: Bearer <token>`

**Response** (200 OK):
```json
{
  "success": true,
  "message": "Logged out successfully"
}
```

### GET /api/v1/auth/verify
**Purpose**: Verify token validity and get current user info

**Headers**: `Authorization: Bearer <token>`

**Response** (200 OK):
```json
{
  "success": true,
  "message": "API token is valid",
  "user": {
    "id": 1,
    "name": "User Name",
    "email": "user@example.com",
    "role": "moderator"
  }
}
```

## Songs Endpoints

### GET /api/v1/songs
**Purpose**: List songs with pagination and filtering

**Headers**: `Authorization: Bearer <token>`

**Query Parameters**:
- `limit` (integer, default: 50): Number of songs per page
- `offset` (integer, default: 0): Number of songs to skip
- `q` (string): Search query using multi-term AND logic (splits query into terms, requires ALL terms to be found across ANY field)
- `status` (string): Filter by processing status (pending, completed, failed, needs_review)
- `genre_id` (integer): Filter by genre ID
- `artist_id` (integer): Filter by artist ID
- `album_id` (integer): Filter by album ID

**Response** (200 OK):
```json
{
  "success": true,
  "songs": [
    {
      "id": 1,
      "title": "Song Title",
      "artist": "Artist Name",
      "album": "Album Title",
      "genre": "Rock",
      "duration": 180,
      "processing_status": "completed",
      "created_at": "2023-01-01T00:00:00Z",
      "updated_at": "2023-01-01T00:00:00Z",
      "audio_url": "https://example.com/rails/active_storage/blobs/...",
      "stream_url": "https://example.com/api/v1/audio_files/1/stream"
    }
  ],
  "total": 1000,
  "limit": 50,
  "offset": 0
}
```

### GET /api/v1/songs/:id
**Purpose**: Get detailed information about a specific song

**Headers**: `Authorization: Bearer <token>`

**Response** (200 OK):
```json
{
  "success": true,
  "song": {
    "id": 1,
    "title": "Song Title",
    "track_number": 1,
    "duration": 180,
    "file_format": "mp3",
    "file_size": 5242880,
    "processing_status": "completed",
    "processing_error": null,
    "original_filename": "song.mp3",
    "created_at": "2023-01-01T00:00:00Z",
    "updated_at": "2023-01-01T00:00:00Z",
    "artist": {
      "id": 1,
      "name": "Artist Name",
      "country": "USA",
      "formed_year": 1990
    },
    "album": {
      "id": 1,
      "title": "Album Title",
      "release_year": 2023,
      "total_tracks": 12
    },
    "genre": {
      "id": 1,
      "name": "Rock",
      "color": "#ff0000",
      "description": "Rock music"
    },
    "audio_file_url": "https://example.com/rails/active_storage/blobs/...",
    "stream_url": "https://example.com/api/v1/audio_files/1/stream",
    "download_url": "https://example.com/api/v1/audio_files/1/download"
  }
}
```

### POST /api/v1/songs/bulk_create
**Purpose**: Create multiple songs at once (moderator/admin only)

**Headers**: `Authorization: Bearer <token>`

**Request Body**:
```json
{
  "songs": [
    {
      "title": "Song Title",
      "track_number": 1,
      "duration": 180,
      "file_format": "mp3",
      "file_size": 5242880,
      "artist_name": "Artist Name",
      "album_title": "Album Title",
      "genre_name": "Rock",
      "notes": "Optional notes"
    }
  ]
}
```

**Response** (200 OK):
```json
{
  "success": true,
  "message": "Bulk create completed",
  "results": [
    {
      "success": true,
      "id": 1,
      "title": "Song Title"
    }
  ],
  "summary": {
    "total": 1,
    "successful": 1,
    "failed": 0
  }
}
```

### POST /api/v1/songs/bulk_upload
**Purpose**: Upload audio file with metadata (moderator/admin only)

**Headers**: `Authorization: Bearer <token>`

**Request Body** (multipart/form-data):
- `audio_file` (file): Audio file to upload
- `filename` (string): Original filename
- `title` (string, optional): Song title
- `artist_name` (string, optional): Artist name
- `album_title` (string, optional): Album title
- `genre_name` (string, optional): Genre name
- `track_number` (integer, optional): Track number
- `duration` (integer, optional): Duration in seconds
- `skip_post_processing` (boolean, optional): Skip metadata extraction

**Response** (201 Created):
```json
{
  "success": true,
  "message": "Song uploaded successfully",
  "song": {
    "id": 1,
    "title": "Song Title",
    "processing_status": "needs_review",
    "created_at": "2023-01-01T00:00:00Z"
  }
}
```

### PUT /api/v1/songs/bulk_update
**Purpose**: Update multiple songs at once (moderator/admin only)

**Headers**: `Authorization: Bearer <token>`

**Request Body**:
```json
{
  "songs": [
    {
      "id": 1,
      "title": "Updated Title",
      "artist_name": "Updated Artist"
    }
  ]
}
```

**Response** (200 OK):
```json
{
  "success": true,
  "message": "Bulk update completed",
  "results": [
    {
      "success": true,
      "id": 1,
      "title": "Updated Title"
    }
  ],
  "summary": {
    "total": 1,
    "successful": 1,
    "failed": 0
  }
}
```

### DELETE /api/v1/songs/bulk_destroy
**Purpose**: Delete multiple songs at once (admin only)

**Headers**: `Authorization: Bearer <token>`

**Request Body**:
```json
{
  "song_ids": [1, 2, 3, 4, 5]
}
```

**Response** (200 OK):
```json
{
  "success": true,
  "message": "Bulk delete completed",
  "deleted_count": 5,
  "requested_count": 5
}
```

### GET /api/v1/songs/export
**Purpose**: Export all songs to JSON format (moderator/admin only)

**Headers**: `Authorization: Bearer <token>`

**Query Parameters**:
- `format` (string, optional): Export format (`json`, `csv`, default: `json`)
- `limit` (integer, optional): Maximum number of songs to export (default: all)
- `offset` (integer, optional): Number of songs to skip (default: 0)
- `fields` (string, optional): Comma-separated list of fields to include (default: all)

**Response** (200 OK):
```json
{
  "success": true,
  "export": {
    "format": "json",
    "total_count": 1000,
    "exported_count": 1000,
    "generated_at": "2023-01-01T00:00:00Z"
  },
  "songs": [
    {
      "id": 1,
      "title": "Song Title",
      "artist": "Artist Name",
      "album": "Album Title",
      "genre": "Rock",
      "duration": 180,
      "processing_status": "completed",
      "created_at": "2023-01-01T00:00:00Z",
      "updated_at": "2023-01-01T00:00:00Z"
    }
  ]
}
```

**CSV Export** (when `format=csv`):
- Returns CSV file download with proper headers
- Content-Type: `text/csv`
- Content-Disposition: `attachment; filename="songs_export_YYYYMMDD_HHMMSS.csv"`

### POST /api/v1/songs/direct_upload
**Purpose**: Get direct upload URL for Active Storage (moderator/admin only)

**Headers**: `Authorization: Bearer <token>`

**Request Body**:
```json
{
  "filename": "song.mp3",
  "content_type": "audio/mpeg",
  "byte_size": 5242880,
  "checksum": "optional_checksum"
}
```

**Response** (200 OK):
```json
{
  "success": true,
  "direct_upload": {
    "url": "https://storage.example.com/upload",
    "headers": {
      "Content-Type": "audio/mpeg"
    },
    "signed_id": "signed_blob_id"
  }
}
```

### POST /api/v1/songs/create_from_blob
**Purpose**: Create song record from uploaded blob (moderator/admin only)

**Headers**: `Authorization: Bearer <token>`

**Request Body**:
```json
{
  "blob_signed_id": "signed_blob_id",
  "filename": "song.mp3",
  "metadata": {
    "title": "Song Title",
    "artist_name": "Artist Name",
    "album_title": "Album Title",
    "genre_name": "Rock"
  },
  "skip_post_processing": false
}
```

**Response** (201 Created):
```json
{
  "success": true,
  "message": "Song created successfully from blob",
  "song": {
    "id": 1,
    "title": "Song Title",
    "processing_status": "needs_review",
    "created_at": "2023-01-01T00:00:00Z"
  }
}
```

## Artists Endpoints

### GET /api/v1/artists
**Purpose**: List artists with pagination and search

**Headers**: `Authorization: Bearer <token>`

**Query Parameters**:
- `limit` (integer, default: 50): Number of artists per page
- `offset` (integer, default: 0): Number of artists to skip
- `search` (string): Search query for artist name or country

**Response** (200 OK):
```json
{
  "success": true,
  "artists": [
    {
      "id": 1,
      "name": "Artist Name",
      "country": "USA",
      "formed_year": 1990,
      "song_count": 25,
      "album_count": 3,
      "created_at": "2023-01-01T00:00:00Z"
    }
  ],
  "total": 100,
  "limit": 50,
  "offset": 0
}
```

### GET /api/v1/artists/:id
**Purpose**: Get detailed information about a specific artist

**Headers**: `Authorization: Bearer <token>`

**Response** (200 OK):
```json
{
  "success": true,
  "artist": {
    "id": 1,
    "name": "Artist Name",
    "biography": "Artist biography...",
    "country": "USA",
    "formed_year": 1990,
    "website": "https://artist.com",
    "song_count": 25,
    "album_count": 3,
    "songs": [
      {
        "id": 1,
        "title": "Song Title",
        "album": "Album Title",
        "duration": 180
      }
    ],
    "albums": [
      {
        "id": 1,
        "title": "Album Title",
        "release_year": 2023,
        "song_count": 12
      }
    ],
    "created_at": "2023-01-01T00:00:00Z"
  }
}
```

### POST /api/v1/artists/bulk_create
**Purpose**: Create multiple artists at once (moderator/admin only)

**Headers**: `Authorization: Bearer <token>`

**Request Body**:
```json
{
  "artists": [
    {
      "name": "Artist Name",
      "country": "USA",
      "formed_year": 1990,
      "biography": "Artist biography...",
      "website": "https://artist.com"
    }
  ]
}
```

**Response** (200 OK):
```json
{
  "success": true,
  "message": "Bulk create completed",
  "results": [
    {
      "success": true,
      "id": 1,
      "name": "Artist Name"
    }
  ],
  "summary": {
    "total": 1,
    "successful": 1,
    "failed": 0
  }
}
```

### GET /api/v1/artists/export
**Purpose**: Export all artists to JSON format (moderator/admin only)

**Headers**: `Authorization: Bearer <token>`

**Query Parameters**:
- `format` (string, optional): Export format (`json`, `csv`, default: `json`)
- `limit` (integer, optional): Maximum number of artists to export (default: all)
- `offset` (integer, optional): Number of artists to skip (default: 0)

**Response** (200 OK):
```json
{
  "success": true,
  "export": {
    "format": "json",
    "total_count": 100,
    "exported_count": 100,
    "generated_at": "2023-01-01T00:00:00Z"
  },
  "artists": [
    {
      "id": 1,
      "name": "Artist Name",
      "country": "USA",
      "formed_year": 1990,
      "song_count": 25,
      "album_count": 3,
      "created_at": "2023-01-01T00:00:00Z"
    }
  ]
}
```

## Albums Endpoints

### GET /api/v1/albums
**Purpose**: List albums with pagination and search

**Headers**: `Authorization: Bearer <token>`

**Query Parameters**:
- `limit` (integer, default: 50): Number of albums per page
- `offset` (integer, default: 0): Number of albums to skip
- `search` (string): Search query for album title or artist name
- `artist_id` (integer): Filter by artist ID

**Response** (200 OK):
```json
{
  "success": true,
  "albums": [
    {
      "id": 1,
      "title": "Album Title",
      "artist": "Artist Name",
      "release_year": 2023,
      "total_tracks": 12,
      "song_count": 12,
      "cover_image_url": "https://example.com/cover.jpg",
      "created_at": "2023-01-01T00:00:00Z"
    }
  ],
  "total": 50,
  "limit": 50,
  "offset": 0
}
```

### GET /api/v1/albums/:id
**Purpose**: Get detailed information about a specific album

**Headers**: `Authorization: Bearer <token>`

**Response** (200 OK):
```json
{
  "success": true,
  "album": {
    "id": 1,
    "title": "Album Title",
    "artist": {
      "id": 1,
      "name": "Artist Name"
    },
    "release_year": 2023,
    "total_tracks": 12,
    "duration": 2400,
    "cover_image_url": "https://example.com/cover.jpg",
    "song_count": 12,
    "songs": [
      {
        "id": 1,
        "title": "Song Title",
        "track_number": 1,
        "duration": 180,
        "genre": "Rock"
      }
    ],
    "created_at": "2023-01-01T00:00:00Z"
  }
}
```

### POST /api/v1/albums/bulk_create
**Purpose**: Create multiple albums at once (moderator/admin only)

**Headers**: `Authorization: Bearer <token>`

**Request Body**:
```json
{
  "albums": [
    {
      "title": "Album Title",
      "artist_name": "Artist Name",
      "release_year": 2023,
      "total_tracks": 12
    }
  ]
}
```

**Response** (200 OK):
```json
{
  "success": true,
  "message": "Bulk create completed",
  "results": [
    {
      "success": true,
      "id": 1,
      "title": "Album Title"
    }
  ],
  "summary": {
    "total": 1,
    "successful": 1,
    "failed": 0
  }
}
```

### GET /api/v1/albums/export
**Purpose**: Export all albums to JSON format (moderator/admin only)

**Headers**: `Authorization: Bearer <token>`

**Query Parameters**:
- `format` (string, optional): Export format (`json`, `csv`, default: `json`)
- `limit` (integer, optional): Maximum number of albums to export (default: all)
- `offset` (integer, optional): Number of albums to skip (default: 0)

**Response** (200 OK):
```json
{
  "success": true,
  "export": {
    "format": "json",
    "total_count": 50,
    "exported_count": 50,
    "generated_at": "2023-01-01T00:00:00Z"
  },
  "albums": [
    {
      "id": 1,
      "title": "Album Title",
      "artist": "Artist Name",
      "release_year": 2023,
      "song_count": 12,
      "cover_image_url": "https://example.com/cover.jpg",
      "created_at": "2023-01-01T00:00:00Z"
    }
  ]
}
```

## Genres Endpoints

### GET /api/v1/genres
**Purpose**: List genres with pagination and search

**Headers**: `Authorization: Bearer <token>`

**Query Parameters**:
- `limit` (integer, default: 50): Number of genres per page
- `offset` (integer, default: 0): Number of genres to skip
- `search` (string): Search query for genre name

**Response** (200 OK):
```json
{
  "success": true,
  "genres": [
    {
      "id": 1,
      "name": "Rock",
      "color": "#ff0000",
      "description": "Rock music",
      "song_count": 150,
      "created_at": "2023-01-01T00:00:00Z"
    }
  ],
  "total": 20,
  "limit": 50,
  "offset": 0
}
```

### GET /api/v1/genres/:id
**Purpose**: Get detailed information about a specific genre

**Headers**: `Authorization: Bearer <token>`

**Response** (200 OK):
```json
{
  "success": true,
  "genre": {
    "id": 1,
    "name": "Rock",
    "color": "#ff0000",
    "description": "Rock music",
    "song_count": 150,
    "songs": [
      {
        "id": 1,
        "title": "Song Title",
        "artist": "Artist Name",
        "album": "Album Title",
        "duration": 180
      }
    ],
    "created_at": "2023-01-01T00:00:00Z"
  }
}
```

### POST /api/v1/genres/bulk_create
**Purpose**: Create multiple genres at once (moderator/admin only)

**Headers**: `Authorization: Bearer <token>`

**Request Body**:
```json
{
  "genres": [
    {
      "name": "Rock",
      "color": "#ff0000",
      "description": "Rock music"
    }
  ]
}
```

**Response** (200 OK):
```json
{
  "success": true,
  "message": "Bulk create completed",
  "results": [
    {
      "success": true,
      "id": 1,
      "name": "Rock"
    }
  ],
  "summary": {
    "total": 1,
    "successful": 1,
    "failed": 0
  }
}
```

### GET /api/v1/genres/export
**Purpose**: Export all genres to JSON format (moderator/admin only)

**Headers**: `Authorization: Bearer <token>`

**Query Parameters**:
- `format` (string, optional): Export format (`json`, `csv`, default: `json`)
- `limit` (integer, optional): Maximum number of genres to export (default: all)
- `offset` (integer, optional): Number of genres to skip (default: 0)

**Response** (200 OK):
```json
{
  "success": true,
  "export": {
    "format": "json",
    "total_count": 20,
    "exported_count": 20,
    "generated_at": "2023-01-01T00:00:00Z"
  },
  "genres": [
    {
      "id": 1,
      "name": "Rock",
      "color": "#ff0000",
      "description": "Rock music",
      "song_count": 150,
      "created_at": "2023-01-01T00:00:00Z"
    }
  ]
}
```

## Playlists Endpoints

### GET /api/v1/playlists
**Purpose**: List playlists accessible to the user

**Headers**: `Authorization: Bearer <token>`

**Query Parameters**:
- `page` (integer, default: 1): Page number
- `per_page` (integer, default: 20): Number of playlists per page
- `user_id` (integer, optional): Filter by user ID (admin only)

**Response** (200 OK):
```json
{
  "success": true,
  "playlists": [
    {
      "id": 1,
      "name": "My Playlist",
      "description": "A great playlist",
      "is_public": true,
      "song_count": 25,
      "user": {
        "id": 1,
        "name": "User Name",
        "email": "user@example.com"
      },
      "created_at": "2023-01-01T00:00:00Z"
    }
  ],
  "pagination": {
    "current_page": 1,
    "total_pages": 5,
    "total_count": 100
  }
}
```

### GET /api/v1/playlists/:id
**Purpose**: Get detailed information about a specific playlist

**Headers**: `Authorization: Bearer <token>`

**Response** (200 OK):
```json
{
  "success": true,
  "playlist": {
    "id": 1,
    "name": "My Playlist",
    "description": "A great playlist",
    "is_public": true,
    "song_count": 25,
    "user": {
      "id": 1,
      "name": "User Name",
      "email": "user@example.com"
    },
    "songs": [
      {
        "id": 1,
        "title": "Song Title",
        "track_number": 1,
        "duration": 180,
        "position": 1,
        "artist": {
          "id": 1,
          "name": "Artist Name"
        },
        "album": {
          "id": 1,
          "title": "Album Title"
        },
        "genre": {
          "id": 1,
          "name": "Rock"
        },
        "audio_file_url": "https://example.com/rails/active_storage/blobs/...",
        "stream_url": "https://example.com/api/v1/audio_files/1/stream"
      }
    ],
    "created_at": "2023-01-01T00:00:00Z"
  }
}
```

### POST /api/v1/playlists/:id/add_song
**Purpose**: Add a song to a playlist (playlist owner only)

**Headers**: `Authorization: Bearer <token>`

**Request Body**:
```json
{
  "song_id": 1,
  "position": 5
}
```

**Response** (200 OK):
```json
{
  "success": true,
  "message": "Song added to playlist",
  "playlist": {
    /* full playlist object with updated songs */
  }
}
```

### DELETE /api/v1/playlists/:id/remove_song
**Purpose**: Remove a song from a playlist (playlist owner only)

**Headers**: `Authorization: Bearer <token>`

**Request Body**:
```json
{
  "song_id": 1
}
```

**Response** (200 OK):
```json
{
  "success": true,
  "message": "Song removed from playlist",
  "playlist": {
    /* full playlist object with updated songs */
  }
}
```

### PUT /api/v1/playlists/:id/reorder_songs
**Purpose**: Reorder songs in a playlist (playlist owner only)

**Headers**: `Authorization: Bearer <token>`

**Request Body**:
```json
{
  "song_order": [3, 1, 2, 5, 4]
}
```

**Response** (200 OK):
```json
{
  "success": true,
  "message": "Playlist reordered successfully",
  "playlist": {
    /* full playlist object with reordered songs */
  }
}
```

## Audio Files Endpoints

### GET /api/v1/audio_files/:id
**Purpose**: Get audio file metadata and URLs

**Headers**: `Authorization: Bearer <token>`

**Response** (200 OK):
```json
{
  "success": true,
  "song_id": 1,
  "title": "Song Title",
  "artist": "Artist Name",
  "album": "Album Title",
  "duration": 180,
  "file_format": "mp3",
  "file_size": 5242880,
  "stream_url": "https://example.com/api/v1/audio_files/1/stream",
  "download_url": "https://example.com/api/v1/audio_files/1/download"
}
```

### GET /api/v1/audio_files/:id/stream
**Purpose**: Stream audio file with range request support

**Headers**: `Authorization: Bearer <token>`

**Optional Headers**:
- `Range: bytes=0-1023` (for partial content requests)

**Response** (200 OK or 206 Partial Content):
- Content-Type: audio/mpeg (or appropriate audio type)
- Accept-Ranges: bytes
- Content-Length: file size (or range size for partial requests)
- Content-Range: bytes 0-1023/5242880 (for partial requests)

**Stream Response**: Binary audio data

### GET /api/v1/audio_files/:id/download
**Purpose**: Download audio file

**Headers**: `Authorization: Bearer <token>`

**Response** (200 OK):
- Content-Type: audio/mpeg (or appropriate audio type)
- Content-Disposition: attachment; filename="Artist - Song.mp3"
- Content-Length: file size

**Download Response**: Binary audio data

## Health Check Endpoint

### GET /api/v1/health
**Purpose**: Check system health and API availability

**Headers**: None required

**Response** (200 OK):
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

**Response** (503 Service Unavailable):
```json
{
  "status": "unhealthy",
  "timestamp": "2023-01-01T00:00:00Z",
  "checks": {
    "database": false,
    "storage": true,
    "search": true
  },
  "version": "1.0.0"
}
```

## Search Endpoints

### GET /api/v1/search
**Purpose**: Global search across all content types with fast results

**Headers**: `Authorization: Bearer <token>`

**Query Parameters**:
- `q` (string, required): Search query
- `type` (string, optional): Content type filter (`songs`, `artists`, `albums`, `genres`, `all`)
- `mode` (string, optional): Search mode (`multi_term` for AND logic, `full_text` for relevance-based, default: `multi_term`)
- `limit` (integer, default: 20): Number of results per content type
- `offset` (integer, default: 0): Number of results to skip

**Search Modes**:
- **`multi_term`**: Splits query into terms, requires ALL terms to be found across ANY field (current songs view behavior)
- **`full_text`**: Uses PostgreSQL full-text search with relevance ranking

**Response** (200 OK):
```json
{
  "success": true,
  "query": "strait run",
  "mode": "multi_term",
  "results": {
    "songs": [
      {
        "id": 1,
        "title": "Strait Run",
        "artist": "Artist Name",
        "album": "Album Title",
        "genre": "Rock",
        "duration": 180,
        "match_score": null
      }
    ],
    "artists": [
      {
        "id": 1,
        "name": "Strait Run Band",
        "song_count": 5,
        "match_score": null
      }
    ],
    "albums": [
      {
        "id": 1,
        "title": "Strait Run Collection",
        "artist": "Artist Name",
        "song_count": 12,
        "match_score": null
      }
    ],
    "genres": []
  },
  "summary": {
    "total_results": 3,
    "songs_count": 1,
    "artists_count": 1,
    "albums_count": 1,
    "genres_count": 0
  },
  "pagination": {
    "limit": 20,
    "offset": 0,
    "has_more": false
  }
}
```

### GET /api/v1/search/songs
**Purpose**: Advanced song search with filtering and fast results

**Headers**: `Authorization: Bearer <token>`

**Query Parameters**:
- `q` (string, required): Search query
- `mode` (string, optional): Search mode (`multi_term`, `full_text`, default: `multi_term`)
- `artist_id` (integer, optional): Filter by artist ID
- `album_id` (integer, optional): Filter by album ID
- `genre_id` (integer, optional): Filter by genre ID
- `status` (string, optional): Filter by processing status
- `duration_min` (integer, optional): Minimum duration in seconds
- `duration_max` (integer, optional): Maximum duration in seconds
- `limit` (integer, default: 50): Number of results per page
- `offset` (integer, default: 0): Number of results to skip
- `sort` (string, optional): Sort order (`relevance`, `title`, `artist`, `album`, `created_at`, default: `relevance` for full_text, `created_at` for multi_term)

**Response** (200 OK):
```json
{
  "success": true,
  "query": "strait run",
  "mode": "multi_term",
  "filters": {
    "artist_id": null,
    "album_id": null,
    "genre_id": null,
    "status": null,
    "duration_min": null,
    "duration_max": null
  },
  "songs": [
    {
      "id": 1,
      "title": "Strait Run",
      "artist": "Artist Name",
      "album": "Album Title",
      "genre": "Rock",
      "duration": 180,
      "processing_status": "completed",
      "created_at": "2023-01-01T00:00:00Z",
      "match_score": null,
      "stream_url": "https://example.com/api/v1/audio_files/1/stream"
    }
  ],
  "total": 1,
  "limit": 50,
  "offset": 0,
  "has_more": false
}
```

### GET /api/v1/search/artists
**Purpose**: Fast artist search with filtering

**Headers**: `Authorization: Bearer <token>`

**Query Parameters**:
- `q` (string, required): Search query
- `mode` (string, optional): Search mode (`multi_term`, `full_text`, default: `multi_term`)
- `country` (string, optional): Filter by country
- `has_songs` (boolean, optional): Only artists with songs
- `limit` (integer, default: 20): Number of results per page
- `offset` (integer, default: 0): Number of results to skip

**Response** (200 OK):
```json
{
  "success": true,
  "query": "beatles",
  "mode": "multi_term",
  "artists": [
    {
      "id": 1,
      "name": "The Beatles",
      "country": "UK",
      "formed_year": 1960,
      "song_count": 150,
      "album_count": 12,
      "match_score": null
    }
  ],
  "total": 1,
  "limit": 20,
  "offset": 0,
  "has_more": false
}
```

### GET /api/v1/search/albums
**Purpose**: Fast album search with filtering

**Headers**: `Authorization: Bearer <token>`

**Query Parameters**:
- `q` (string, required): Search query
- `mode` (string, optional): Search mode (`multi_term`, `full_text`, default: `multi_term`)
- `artist_id` (integer, optional): Filter by artist ID
- `release_year_min` (integer, optional): Minimum release year
- `release_year_max` (integer, optional): Maximum release year
- `has_songs` (boolean, optional): Only albums with songs
- `limit` (integer, default: 20): Number of results per page
- `offset` (integer, default: 0): Number of results to skip

**Response** (200 OK):
```json
{
  "success": true,
  "query": "abbey road",
  "mode": "multi_term",
  "albums": [
    {
      "id": 1,
      "title": "Abbey Road",
      "artist": "The Beatles",
      "release_year": 1969,
      "song_count": 17,
      "cover_image_url": "https://example.com/cover.jpg",
      "match_score": null
    }
  ],
  "total": 1,
  "limit": 20,
  "offset": 0,
  "has_more": false
}
```

### GET /api/v1/search/suggestions
**Purpose**: Get search suggestions for autocomplete functionality

**Headers**: `Authorization: Bearer <token>`

**Query Parameters**:
- `q` (string, required): Partial search query (minimum 2 characters)
- `type` (string, optional): Content type (`songs`, `artists`, `albums`, `genres`, `all`, default: `all`)
- `limit` (integer, default: 10): Number of suggestions per type

**Response** (200 OK):
```json
{
  "success": true,
  "query": "stra",
  "suggestions": {
    "songs": [
      {
        "id": 1,
        "title": "Strait Run",
        "artist": "Artist Name",
        "type": "song"
      }
    ],
    "artists": [
      {
        "id": 1,
        "name": "Strait Run Band",
        "type": "artist"
      }
    ],
    "albums": [
      {
        "id": 1,
        "title": "Strait Run Collection",
        "artist": "Artist Name",
        "type": "album"
      }
    ],
    "genres": []
  }
}
```

## Missing Endpoints (To Be Implemented)

### User Management Endpoints
- `GET /api/v1/users` - List users (admin only)
- `POST /api/v1/users` - Create user (admin only)
- `GET /api/v1/users/:id` - Get user details (admin only)
- `PUT /api/v1/users/:id` - Update user (admin only)
- `DELETE /api/v1/users/:id` - Delete user (admin only)
- `POST /api/v1/users/:id/reset_password` - Reset user password (admin only)

### Playlist Management Endpoints
- `POST /api/v1/playlists` - Create new playlist
- `PUT /api/v1/playlists/:id` - Update playlist details
- `DELETE /api/v1/playlists/:id` - Delete playlist

### Statistics Endpoints
- `GET /api/v1/stats` - System statistics (admin only)
- `GET /api/v1/stats/songs` - Song statistics
- `GET /api/v1/stats/users` - User statistics (admin only)

### System Endpoints
- `GET /api/v1/system/settings` - Get system settings (admin only)
- `PUT /api/v1/system/settings` - Update system settings (admin only)
- `GET /api/v1/system/status` - Detailed system status (admin only)

## Implementation Notes

### Rails Tools & Best Practices
1. **API Versioning**: Use Rails API versioning with namespaced controllers
2. **Serializers**: Use `active_model_serializers` for consistent JSON responses
3. **Error Handling**: Implement standardized error handling with custom exception classes
4. **Service Objects**: Use service objects for complex business logic (search, bulk operations)
5. **Built-in Caching**: Leverage Rails built-in caching for frequently accessed data
6. **Background Jobs**: Use Rails built-in ActiveJob for bulk operations and file processing

### Active Model Serializers Implementation
**Benefits:**
- Consistent JSON structure across all endpoints
- Easy to maintain and update
- Built-in association handling
- Custom attribute methods
- Versioning support

**Example Implementation:**
```ruby
# Gemfile
gem 'active_model_serializers'

# app/serializers/song_serializer.rb
class SongSerializer < ActiveModel::Serializer
  attributes :id, :title, :track_number, :duration, :file_format, 
             :file_size, :processing_status, :created_at, :updated_at
  
  belongs_to :artist, serializer: ArtistSerializer
  belongs_to :album, serializer: AlbumSerializer  
  belongs_to :genre, serializer: GenreSerializer
  
  def audio_url
    object.audio_file.attached? ? rails_blob_url(object.audio_file) : nil
  end
  
  def stream_url
    object.audio_file.attached? ? api_v1_audio_file_stream_url(object) : nil
  end
  
  def download_url
    object.audio_file.attached? ? api_v1_audio_file_download_url(object) : nil
  end
end

# app/controllers/api/v1/songs_controller.rb
def index
  @songs = Song.includes(:artist, :album, :genre)
               .page(params[:page])
               .per(params[:per_page] || 50)
  
  render json: @songs, each_serializer: SongSerializer
end

def show
  @song = Song.includes(:artist, :album, :genre).find(params[:id])
  render json: @song, serializer: SongSerializer
end
```

**Usage in Controllers:**
```ruby
# Instead of manual JSON building:
render json: {
  success: true,
  songs: @songs.map { |song| song_to_json(song) }
}

# Use serializers:
render json: {
  success: true,
  songs: ActiveModelSerializers::SerializableResource.new(@songs, each_serializer: SongSerializer)
}
```

### Authentication Options

#### Current Token System (CRITICAL SECURITY ISSUE)
**⚠️ SECURITY WARNING: This system is vulnerable to attack!**

**Vulnerabilities:**
- ❌ **No cryptographic signature** - Anyone can create valid tokens
- ❌ **Role escalation** - Users can promote themselves to admin
- ❌ **User impersonation** - Can access any user's data
- ❌ **No tamper detection** - Tokens can be modified
- ❌ **No revocation** - Compromised tokens work for 30 days

**DO NOT USE ON PUBLIC INTERNET**

#### JWT Authentication (REQUIRED FOR PUBLIC INTERNET)
**Pros:**
- ✅ **Cryptographically signed** - Tamper-proof tokens
- ✅ **Industry standard** - Widely supported
- ✅ **Built-in expiration** - Automatic handling
- ✅ **Custom claims** - Can include additional data
- ✅ **Stateless** - No database lookups required

**Cons:**
- ⚠️ **Additional complexity** - Requires JWT gem
- ⚠️ **Larger token size** - More bandwidth usage
- ⚠️ **No built-in revocation** - Need separate revocation system

**Implementation Required:**
```ruby
# Gemfile
gem 'jwt'

# Token generation
payload = {
  user_id: user.id,
  email: user.email,
  role: user.role,
  exp: 30.days.from_now.to_i,
  iat: Time.current.to_i,
  jti: SecureRandom.uuid
}
token = JWT.encode(payload, Rails.application.secret_key_base, 'HS256')

# Token validation
payload = JWT.decode(token, Rails.application.secret_key_base, true, { algorithm: 'HS256' })[0]
```

#### API Token System (Future Enhancement)
For long-lived tokens (weekend jukebox use):
- Generate persistent API tokens stored in database
- User can create/revoke their own tokens
- Tokens can have custom expiration (hours to months)
- Better for external integrations

**Implementation:**
```ruby
# Add to User model
has_many :api_tokens, dependent: :destroy

# New model: ApiToken
class ApiToken < ApplicationRecord
  belongs_to :user
  validates :name, presence: true
  validates :token, presence: true, uniqueness: true
  
  before_create :generate_token
  
  def expired?
    expires_at.present? && expires_at < Time.current
  end
  
  private
  
  def generate_token
    self.token = SecureRandom.urlsafe_base64(32)
  end
end
```

### Security Considerations (CRITICAL FOR PUBLIC INTERNET)
1. **JWT Authentication**: REQUIRED - Replace current token system immediately
2. **Rate Limiting**: REQUIRED - Implement rack-attack for API protection
3. **Input Validation**: Use strong parameters and model validations
4. **SQL Injection**: Use parameterized queries and avoid raw SQL
5. **File Upload Security**: Validate file types and scan for malware
6. **CORS**: Configure CORS properly for web client access
7. **HTTPS**: Enforce HTTPS in production (force_ssl = true)
8. **Security Headers**: Add proper security headers
9. **Token Revocation**: Implement API token revocation system
10. **Audit Logging**: Log all API access and security events

### Immediate Security Actions Required
1. **Disable API endpoints** until JWT is implemented
2. **Implement JWT authentication** with proper signing
3. **Add rate limiting** to prevent brute force attacks
4. **Force HTTPS** in production
5. **Add security headers** and CORS configuration
6. **Implement token revocation** system
7. **Add audit logging** for security monitoring

### Performance Optimizations
1. **Database Indexing**: Ensure proper indexes on frequently queried fields
2. **Eager Loading**: Use `includes` to avoid N+1 queries
3. **Pagination**: Implement cursor-based pagination for large datasets
4. **Built-in Caching**: Use Rails.cache for expensive operations and frequently accessed data
5. **CDN**: Use CDN for audio file delivery
6. **Compression**: Enable gzip compression for API responses

### Search Performance
1. **Multi-term Search**: Uses ILIKE with proper indexing for fast partial matches
2. **Full-text Search**: Leverages PostgreSQL's `search_vector` and `ts_rank` for relevance-based results
3. **Database Indexes**: Ensure indexes on `title`, `name` fields and `search_vector` columns
4. **Query Optimization**: Use `includes` to preload associations and avoid N+1 queries
5. **Result Caching**: Cache frequent search queries for improved response times
6. **Pagination**: Limit results to prevent large result sets from impacting performance

### Error Handling
1. **Consistent Error Format**: Use standardized error response format
2. **Logging**: Log all API errors with appropriate detail
3. **Monitoring**: Implement API monitoring and alerting
4. **Graceful Degradation**: Handle partial failures gracefully

This API specification provides comprehensive coverage of the Archive music management system, enabling full programmatic control while maintaining security and performance standards.
