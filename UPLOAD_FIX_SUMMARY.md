# Universal Upload Fix Summary

## Problem
The `utilities/universal_upload.py` script was failing with a **404 error** when trying to upload files to `/api/v1/songs/bulk_upload`. The error message showed an HTML "page not found" response instead of a JSON API response.

## Root Cause
The `/api/v1/songs/bulk_upload` endpoint was defined in the routes file (`archive/config/routes.rb`) but the **implementation was missing** from the `Api::V1::SongsController`. The controller only had `show`, `download`, and `stream` actions, but no `bulk_upload` method.

## What Was Fixed

### 1. Added the `bulk_upload` method to `Api::V1::SongsController`
Location: `archive/app/controllers/api/v1/songs_controller.rb`

The method now:
- Accepts file uploads via multipart/form-data
- Validates that an audio file is provided
- Creates a new Song record with the uploaded file
- Extracts metadata from the audio file (artist, album, title, etc.)
- Automatically finds or creates associated Artist, Album, and Genre records
- Returns proper JSON responses with the uploaded song information
- Handles errors gracefully

### 2. Added proper API authentication
- Included the `EncryptedTokenAuthentication` concern
- This ensures the endpoint uses Bearer token authentication
- Replaced web session authentication (`authenticate_user!`) with API token authentication

### 3. Added permission checks
- Added `ensure_upload_permission!` method to verify user has moderator or admin role
- Only moderators and admins can upload files via the API

### 4. Added the `index` method
- Added a proper index endpoint for listing songs via API
- Includes pagination, sorting, and filtering support

## How to Test

### Step 1: Restart the Archive service
Since we modified the Rails controller, you need to restart the server:

```bash
cd archive
# Stop the current server (Ctrl+C if running)
rails server
# Or if using Docker:
docker-compose restart archive
```

### Step 2: Test the endpoint
Run the test script:

```bash
python utilities/test_upload_fix.py
```

This should return a 401 (unauthorized) or 422 (unprocessable entity) instead of 404, confirming the endpoint exists.

### Step 3: Test with a real upload
Try uploading a single file to verify everything works:

```bash
python utilities/universal_upload.py /path/to/music --username your@email.com --password yourpassword --limit 1 --verbose
```

## Expected Response

When the upload is successful, you should see:
```
✓ Uploaded: songname.mp3 (5.2 MB) -> ID: <uuid>, Status: needs_review
```

Instead of the previous 404 error:
```
✗ Failed to upload: songname.mp3 (5.2 MB) [HTTP 404: <!doctype html>...]
```

## API Endpoint Details

**Endpoint:** `POST /api/v1/songs/bulk_upload`

**Headers:**
```
Authorization: Bearer <api_token>
Content-Type: multipart/form-data
```

**Parameters:**
- `audio_file` (file, required): The audio file to upload
- `filename` (string, optional): Original filename
- `title` (string, optional): Song title
- `artist_name` (string, optional): Artist name
- `album_title` (string, optional): Album title
- `genre_name` (string, optional): Genre name
- `track_number` (integer, optional): Track number
- `duration` (integer, optional): Duration in seconds
- `skip_post_processing` (boolean, optional): Skip metadata extraction

**Success Response (201 Created):**
```json
{
  "success": true,
  "message": "Song uploaded successfully",
  "song": {
    "id": "uuid-here",
    "title": "Song Title",
    "artist": "Artist Name",
    "album": "Album Title",
    "genre": "Genre Name",
    "processing_status": "needs_review",
    "created_at": "2025-10-10T12:34:56Z"
  }
}
```

**Error Response (401 Unauthorized):**
```json
{
  "success": false,
  "message": "Missing API token"
}
```

**Error Response (422 Unprocessable Entity):**
```json
{
  "success": false,
  "message": "No audio file provided"
}
```

## Files Modified

1. `archive/app/controllers/api/v1/songs_controller.rb`
   - Added `EncryptedTokenAuthentication` include
   - Added `index` method
   - Added `bulk_upload` method
   - Added `ensure_upload_permission!` method
   - Updated authentication to use API tokens

## Notes

- The endpoint automatically extracts metadata from uploaded audio files using the existing `extract_metadata_from_file` method in the Song model
- If metadata extraction fails, the song is marked with status `failed` and the error is stored
- If metadata is incomplete, the song is marked with status `needs_review`
- If metadata is complete, the song is marked with status `completed`
- The endpoint requires moderator or admin permissions

## Troubleshooting

### Still getting 404?
- Make sure you restarted the Rails server after making the changes
- Check that the Archive service is actually running on port 3000
- Verify the URL in your upload script matches: `http://localhost:3000`

### Getting 401 Unauthorized?
- Check that you're passing valid credentials to the script
- Verify your user account exists and has the correct permissions
- Try logging in manually via the web interface first

### Getting 403 Forbidden?
- Your user account needs moderator or admin role
- Update your user role in the Rails console:
  ```ruby
  user = User.find_by(email: 'your@email.com')
  user.update(role: 'admin')  # or 'moderator'
  ```

### Uploads succeed but metadata is wrong?
- Check the `processing_status` field in the response
- If it's `failed`, check the `processing_error` field for details
- If it's `needs_review`, you may need to manually edit the metadata in the web UI

