# Archive API Specification

## Overview

This document defines the comprehensive API specification for the Archive music management system. The API provides programmatic access to all core functionality including authentication, music library management, playlist operations, bulk operations, and audio file streaming.

## Project Scope

This API focuses on two primary goals:

1. Bulk ingest of music files and light metadata fixes
   - Supported: direct upload, create from blob, bulk upload, bulk create, light bulk update
   - Not supported: destructive operations (e.g., bulk delete), heavy tag editing workflows

2. Player/Jukebox foundation
   - Supported: fast search, browse, and playback via progressive streaming with HTTP Range
   - Out of scope: adaptive streaming (HLS/DASH) and advanced playlist collaboration features

## API Design Principles

### Authentication & Authorization
- **Token-based Authentication**: All API endpoints require Bearer token authentication
- **Role-based Access Control**: Three user roles (user, moderator, admin) with different permission levels
- **Secure Token Management**: Tokens expire after 2 days and can be verified/refreshed

**Authentication Flow**:
1. Client sends credentials to `/api/v1/auth/login`
2. Server validates credentials and returns a Base64-encoded token
3. Client includes token in all subsequent requests: `Authorization: Bearer <token>`
4. Server validates token on each request and returns user context
5. Token expires after 2 days - client must re-authenticate

### Response Format
All successful responses use a consistent JSON structure. Error responses follow RFC 7807 (application/problem+json).

Successful (2xx) response envelope:
```json
{
  "success": true,
  "message": "Human-readable message",
  "data": { /* response data */ },
  "pagination": { /* pagination info when applicable */ }
}
```

Error response (RFC 7807):
Content-Type: application/problem+json
```json
{
  "type": "about:blank",
  "title": "Unauthorized",
  "status": 401,
  "detail": "Invalid or expired token",
  "instance": "/api/v1/auth/verify"
}
```

Validation error (422) with field details:
```json
{
  "type": "https://api.example.com/problems/validation-error",
  "title": "Unprocessable Entity",
  "status": 422,
  "detail": "Validation failed",
  "errors": { "title": ["can't be blank"], "file_format": ["unsupported"] }
}
```

**JSON-First Design**:
- All API endpoints return JSON by default
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

### Pagination & Sorting Standard
- Pagination params:
  - `limit` (integer, default: 50, max: 500)
  - `offset` (integer, default: 0)
- Sorting params:
  - `sort` (string, optional; per-resource whitelist)
  - `order` (string, `asc` or `desc`, default depends on `sort`)
- Allowed primary sorts:
  - Songs: `title`
  - Artists: `name`
  - Albums: `title`
  - Genres: `name`
  - Playlists: `name`
- Default ordering (deterministic):
  - List endpoints (when `sort` not provided): `created_at desc` with `id` as tiebreaker
  - Search endpoints:
    - `full_text`: `match_score desc, created_at desc` with `id` tiebreaker
    - `multi_term`: `created_at desc` with `id` tiebreaker
- Notes:
  - IDs are UUIDs; use them only as deterministic tie-breakers, not user-facing sorts.
  - The server clamps `limit` to the max and validates `sort` against the whitelist.
  - All list/search responses include `pagination: { total, limit, offset, has_more }`.

### Data Types & ID Conventions
- All resource identifiers are strings containing UUIDs.
- All `id` fields in responses are strings (UUIDs).
- All request parameters and bodies that reference resources (e.g., `artist_id`, `album_id`, `genre_id`, `user_id`, `song_id`, arrays like `song_ids`) MUST be strings (UUIDs).
- Numeric fields (e.g., counts, durations, years, sizes) remain numeric.

### Search Parameters Standard
- Common params:
  - `q` (string): Search query (required unless endpoint specifies otherwise)
  - `mode` (string): `multi_term` (AND term matching) or `full_text` (relevance-ranked). Default: `multi_term`.
  - `limit` (integer, default: 50, max: 500)
  - `offset` (integer, default: 0)
- Global search (`GET /api/v1/search`):
  - `type` (string): One of `songs`, `artists`, `albums`, `genres`, `all` (default: `all`).
  - `limit`/`offset` apply per-type when `type=all`.
  - Sorting is per-type; global endpoint does not accept a single `sort`/`order` parameter.
- Per-resource search (`/api/v1/search/{resource}`):
  - Accept resource-specific filters (e.g., `artist_id`, `album_id`, etc.).
  - Accept `sort` and `order` as defined in Pagination & Sorting Standard with relevance-first default for `full_text`.
  - Echo `mode` in the response body.

### Sparse Fields & Includes
- Purpose: Reduce over-fetching and allow selective embedding of related data.
- Sparse fields:
  - `fields` controls top-level fields on the primary resource list/detail.
  - Per-type overrides for includes via `fields[<type>]`.
  - Example: `?fields=id,title,artist,album,genre,duration` and `&fields[albums]=id,title`
- Includes (whitelisted per resource):
  - Songs may include: `artist,album,genre`
  - Albums may include: `artist,songs`
  - Artists may include: `albums,songs`
  - Genres may include: `songs`
- Limits and safety:
  - Pagination applies to the primary collection only.
  - Embedded collections are bounded by server caps (e.g., first 10); use dedicated endpoints for full pagination.
  - Reject deep nesting and unknown includes.
- Deterministic ordering for embeds:
  - album.songs: `track_number asc, title asc`
  - artist.albums: `release_year asc, title asc`
  - artist.songs / genre.songs: `title asc`
- Examples:
  - Songs list with minimal fields and embedded names:
    - `GET /api/v1/songs?fields=id,title,artist,album,genre&include=artist,album&fields[artists]=id,name&fields[albums]=id,title`
  - Album detail with bounded songs:
    - `GET /api/v1/albums/:id?include=songs&fields[songs]=id,title,track_number`

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
    "id": "6f0d9c2a-9d3b-4a68-8f7f-1a2b3c4d5e6f",
    "name": "User Name",
    "email": "user@example.com",
    "role": "moderator"
  }
}
```

**Error Response** (401 Unauthorized):
Content-Type: application/problem+json
```json
{
  "type": "about:blank",
  "title": "Unauthorized",
  "status": 401,
  "detail": "Invalid email or password"
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
    "id": "6f0d9c2a-9d3b-4a68-8f7f-1a2b3c4d5e6f",
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
- `genre_id` (string): Filter by genre ID (UUID)
- `artist_id` (string): Filter by artist ID (UUID)
- `album_id` (string): Filter by album ID (UUID)
- `sort` (string, optional): One of `created_at`, `title`, `artist`, `album`, `duration`
- `order` (string, optional): `asc` or `desc` (default: `desc` for `created_at`, `asc` for text sorts)

**Response** (200 OK):
```json
{
  "success": true,
  "songs": [
    {
      "id": "2f6c7c80-1d4d-4a4a-8c5a-2e2b2f3d9b1a",
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
    "id": "2f6c7c80-1d4d-4a4a-8c5a-2e2b2f3d9b1a",
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
      "id": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
      "name": "Artist Name",
      "country": "USA",
      "formed_year": 1990
    },
    "album": {
      "id": "0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9",
      "title": "Album Title",
      "release_year": 2023,
      "total_tracks": 12
    },
    "genre": {
      "id": "9e8d7c6b-5a4f-3210-b1a2-c3d4e5f6a7b8",
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

<!-- Removed: songs bulk_create is out of scope; songs are created only via upload endpoints -->

### POST /api/v1/songs/bulk_upload
**Purpose**: Upload audio file with metadata (moderator/admin only). Song records MUST be created with an attached file.

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
    "id": "2f6c7c80-1d4d-4a4a-8c5a-2e2b2f3d9b1a",
    "title": "Song Title",
    "processing_status": "needs_review",
    "created_at": "2023-01-01T00:00:00Z"
  }
}
```

### PUT /api/v1/songs/bulk_update
**Purpose**: Update multiple songs at once (moderator/admin only). Limited to light metadata edits (e.g., `title`, `track_number`, `artist_id`/`album_id`/`genre_id`).

**Headers**: `Authorization: Bearer <token>`

**Request Body**:
```json
{
  "songs": [
    {
      "id": "2f6c7c80-1d4d-4a4a-8c5a-2e2b2f3d9b1a",
      "title": "Updated Title",
      "track_number": 3,
      "artist_id": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
      "album_id": "0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9",
      "genre_id": "9e8d7c6b-5a4f-3210-b1a2-c3d4e5f6a7b8"
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

<!-- Removed: bulk destroy is out of scope for this API -->

<!-- Removed: songs export is out of scope for public API -->

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
- `sort` (string, optional): One of `created_at`, `name`, `song_count`, `album_count`
- `order` (string, optional): `asc` or `desc` (default: `asc` for `name`)

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

<!-- Removed: artists bulk_create is out of scope; artists are created/linked via song upload/edit -->

<!-- Removed: artists export is out of scope for public API -->

## Albums Endpoints

### GET /api/v1/albums
**Purpose**: List albums with pagination and search

**Headers**: `Authorization: Bearer <token>`

**Query Parameters**:
- `limit` (integer, default: 50): Number of albums per page
- `offset` (integer, default: 0): Number of albums to skip
- `search` (string): Search query for album title or artist name
- `artist_id` (string): Filter by artist ID (UUID)
- `sort` (string, optional): One of `created_at`, `title`, `release_year`, `song_count`
- `order` (string, optional): `asc` or `desc` (default: `asc` for `title`)

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

<!-- Removed: albums bulk_create is out of scope; albums are created/linked via song upload/edit -->

<!-- Removed: albums export is out of scope for public API -->

## Genres Endpoints

### GET /api/v1/genres
**Purpose**: List genres with pagination and search

**Headers**: `Authorization: Bearer <token>`

**Query Parameters**:
- `limit` (integer, default: 50): Number of genres per page
- `offset` (integer, default: 0): Number of genres to skip
- `search` (string): Search query for genre name
- `sort` (string, optional): One of `created_at`, `name`, `song_count`
- `order` (string, optional): `asc` or `desc` (default: `asc` for `name`)

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

<!-- Removed: genres bulk_create is out of scope; genres are created/linked via song upload/edit -->

<!-- Removed: genres export is out of scope for public API -->

## Playlists Endpoints

### GET /api/v1/playlists
**Purpose**: List playlists accessible to the user

**Headers**: `Authorization: Bearer <token>`

**Query Parameters**:
- `limit` (integer, default: 20): Number of playlists per page
- `offset` (integer, default: 0): Number of playlists to skip
- `user_id` (string, optional): Filter by user ID (UUID, admin only)
- `sort` (string, optional): One of `created_at`, `name`, `song_count`
- `order` (string, optional): `asc` or `desc` (default: `desc` for `created_at`, `asc` for `name`)

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
  "pagination": { "total": 100, "limit": 20, "offset": 0, "has_more": true }
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
  "song_id": "2f6c7c80-1d4d-4a4a-8c5a-2e2b2f3d9b1a",
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
  "song_id": "2f6c7c80-1d4d-4a4a-8c5a-2e2b2f3d9b1a"
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
  "song_id": "2f6c7c80-1d4d-4a4a-8c5a-2e2b2f3d9b1a",
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
**Purpose**: Progressive streaming with HTTP Range support (no HLS/DASH)

**Headers**: `Authorization: Bearer <token>`

**Optional Headers**:
- `Range: bytes=0-1023` (for partial content requests)

**Response** (200 OK or 206 Partial Content):
- Content-Type: appropriate audio MIME type (e.g., audio/mpeg, audio/mp4, audio/flac)
- Accept-Ranges: bytes
- Content-Length: file size (or range size for partial requests)
- Content-Range: bytes 0-1023/5242880 (for partial requests)

**Stream Response**: Binary audio data

**Notes**:
- Supports HEAD for metadata only (Content-Type, Content-Length, Accept-Ranges).
- Authentication required on each request or via short-lived signed URLs.

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
- `sort` (string, optional): One of `relevance` (full_text only), `created_at`, `title`, `artist`, `album`, `duration`
- `order` (string, optional): `asc` or `desc` (default: `relevance desc` for full_text, otherwise `created_at desc`)

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
- `sort` (string, optional): One of `relevance` (full_text only), `created_at`, `name`, `song_count`, `album_count`
- `order` (string, optional): `asc` or `desc` (default: `relevance desc` for full_text, otherwise `name asc`)

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
- `sort` (string, optional): One of `relevance` (full_text only), `created_at`, `title`, `release_year`, `song_count`
- `order` (string, optional): `asc` or `desc` (default: `relevance desc` for full_text, otherwise `title asc`)

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
               .limit([params[:limit].to_i, 500].compact.min.presence || 50)
               .offset(params[:offset].to_i.presence || 0)
  
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
- ❌ **No revocation** - Compromised tokens work for 2 days

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
  exp: 2.days.from_now.to_i,
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
