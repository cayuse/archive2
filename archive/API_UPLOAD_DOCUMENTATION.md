# API Upload Documentation

## Overview

The API now supports flexible metadata handling for song uploads. You can provide arbitrary metadata parameters during upload, and the system will apply them before any automatic metadata extraction.

## Endpoint

```
POST /api/v1/songs/bulk_upload
```

## Authentication

Include your API token in the Authorization header:
```
Authorization: Bearer <your_api_token>
```

## Parameters

### Required
- `audio_file`: The audio file to upload (multipart/form-data)

### Optional Metadata Parameters
You can provide any of these parameters to set metadata before processing:

- `title`: Song title
- `artist_name` or `artist`: Artist name
- `album_title` or `album`: Album title  
- `genre_name` or `genre`: Genre name
- `track_number`: Track number
- `duration`: Duration in seconds
- `notes`: Additional notes

### Processing Options
- `skip_metadata_extraction`: Set to 'true' to skip automatic metadata extraction from the audio file

## Examples

### Basic Upload (Auto-extract metadata)
```bash
curl -X POST http://localhost:3000/api/v1/songs/bulk_upload \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -F "audio_file=@song.mp3"
```

### Upload with Provided Metadata
```bash
curl -X POST http://localhost:3000/api/v1/songs/bulk_upload \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -F "audio_file=@song.mp3" \
  -F "title=My Song" \
  -F "artist_name=My Artist" \
  -F "album_title=My Album" \
  -F "genre_name=Rock"
```

### Upload with Partial Metadata
```bash
curl -X POST http://localhost:3000/api/v1/songs/bulk_upload \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -F "audio_file=@song.mp3" \
  -F "title=My Song" \
  -F "artist_name=My Artist"
```

### Upload with Skip Metadata Extraction
```bash
curl -X POST http://localhost:3000/api/v1/songs/bulk_upload \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -F "audio_file=@song.mp3" \
  -F "title=My Song" \
  -F "artist_name=My Artist" \
  -F "skip_metadata_extraction=true"
```

## Python Script Usage

Update your Python script to use the new parameters:

```python
# Example with metadata
response = requests.post(
    f"{API_BASE_URL}/songs/bulk_upload",
    headers={"Authorization": f"Bearer {token}"},
    files={"audio_file": open(file_path, "rb")},
    data={
        "title": "Song Title",
        "artist_name": "Artist Name", 
        "album_title": "Album Title",
        "genre_name": "Rock"
    }
)
```

## Processing Status

The system will set the processing status based on provided metadata:

- **`completed`**: All metadata provided (artist, album, genre)
- **`needs_review`**: Partial metadata provided
- **`processing`**: No metadata provided, will extract from file
- **`new`**: Skip metadata extraction, minimal processing

## Response Format

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

## Error Handling

If metadata extraction fails, the song will still be saved with:
- The original filename as title
- Any provided metadata applied
- Processing status set appropriately

## Benefits

1. **Flexible**: Provide any combination of metadata parameters
2. **Backward Compatible**: Existing scripts continue to work
3. **Efficient**: Skip metadata extraction when you have complete info
4. **Reliable**: Songs are always saved, even if processing fails
5. **Extensible**: Easy to add new metadata fields in the future 