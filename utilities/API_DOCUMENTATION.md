# Music Archive API Documentation

## Authentication

The API uses Bearer token authentication. To get an API token:

### Login
```bash
curl -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "your_email@example.com",
    "password": "your_password"
  }'
```

Response:
```json
{
  "success": true,
  "message": "Authentication successful",
  "api_token": "eyJ1c2VyX2lkIjoxLCJlbWFpbCI6InRlc3RAZXhhbXBsZS5jb20iLCJyb2xlIjoidXNlciIsImV4cCI6MTczNDU2NzIwMH0=",
  "user": {
    "id": 1,
    "name": "Test User",
    "email": "test@example.com",
    "role": "admin"
  }
}
```

### Verify Token
```bash
curl -X GET http://localhost:3000/api/v1/auth/verify \
  -H "Authorization: Bearer YOUR_API_TOKEN"
```

## Bulk Upload API

### Upload Single Song
```bash
curl -X POST http://localhost:3000/api/v1/songs/bulk_upload \
  -H "Authorization: Bearer YOUR_API_TOKEN" \
  -F "audio_file=@/path/to/song.mp3"
```

Response:
```json
{
  "success": true,
  "message": "Song uploaded successfully",
  "song": {
    "id": 123,
    "title": "Song Title",
    "status": "processing",
    "created_at": "2024-01-15T10:30:00Z"
  }
}
```

### Bulk Create Songs
```bash
curl -X POST http://localhost:3000/api/v1/songs/bulk_create \
  -H "Authorization: Bearer YOUR_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "songs": [
      {
        "title": "Song 1",
        "artist_id": 1,
        "album_id": 1,
        "genre_id": 1,
        "status": "complete"
      },
      {
        "title": "Song 2",
        "artist_id": 2,
        "status": "needs_review"
      }
    ]
  }'
```

### Get Songs List
```bash
curl -X GET "http://localhost:3000/api/v1/songs?limit=10&offset=0" \
  -H "Authorization: Bearer YOUR_API_TOKEN"
```

### Export Songs
```bash
curl -X GET http://localhost:3000/api/v1/songs/export \
  -H "Authorization: Bearer YOUR_API_TOKEN" \
  -o songs_export.csv
```

## Status Codes

- `200` - Success
- `201` - Created (for uploads)
- `400` - Bad Request
- `401` - Unauthorized
- `403` - Forbidden
- `422` - Unprocessable Entity
- `500` - Internal Server Error

## Song Status Values

- `processing` - File uploaded, metadata extraction in progress
- `complete` - All metadata extracted successfully
- `needs_review` - Metadata incomplete, requires manual review
- `error` - Processing failed

## Supported Audio Formats

- MP3 (.mp3)
- WAV (.wav)
- FLAC (.flac)
- M4A (.m4a)
- OGG (.ogg)
- AAC (.aac)

## Permissions

- **Admin/Moderator**: Can upload songs and perform all bulk operations
- **Regular User**: Can only view songs (read-only access)

## Error Handling

All API responses include a `success` field and appropriate error messages:

```json
{
  "success": false,
  "message": "Error description",
  "errors": ["Detailed error 1", "Detailed error 2"]
}
``` 