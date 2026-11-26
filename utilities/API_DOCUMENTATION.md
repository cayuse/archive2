# API used by the upload scripts

The two endpoints the scripts in this directory call. The whole API is documented in
`../docs/reference/archive_api.md`.

## Log in

```bash
curl -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "you@example.com", "password": "your_password"}'
```

```json
{
  "success": true,
  "message": "Authentication successful",
  "api_token": "…",
  "expires_at": 1795000000,
  "user": { "id": "6f0d9c2a-9d3b-4a68-8f7f-1a2b3c4d5e6f", "name": "You", "email": "you@example.com", "role": "admin" }
}
```

The token lasts 2 days. Add `"expires_in": <seconds>` (up to 30 days) for a longer one.
Check a token with:

```bash
curl http://localhost:3000/api/v1/auth/verify -H "Authorization: Bearer $API_TOKEN"
```

## Upload a song

One file per request. The account must be a moderator or an admin.

```bash
curl -X POST http://localhost:3000/api/v1/songs/bulk_upload \
  -H "Authorization: Bearer $API_TOKEN" \
  -F "audio_file=@/path/to/song.mp3"
```

Optional form fields: `filename`, `title`, `artist_name`, `album_title`, `genre_name`,
`track_number`, `duration`, `skip_post_processing=true`.

Response, 201:

```json
{
  "success": true,
  "message": "Song uploaded successfully",
  "song": {
    "id": "2f6c7c80-1d4d-4a4a-8c5a-2e2b2f3d9b1a",
    "title": "Song Title",
    "artist": "Artist Name",
    "album": "Album Title",
    "genre": "Rock",
    "processing_status": "completed",
    "created_at": "2026-01-15T10:30:00.000Z"
  }
}
```

`processing_status` is `completed` (the song has a title and an artist), `needs_review`
(it does not; fix it on the Maintenance page) or `failed`.

## Errors

| Status | Meaning |
|---|---|
| 401 | missing, invalid or expired token; wrong email or password |
| 403 | the account is not a moderator or admin |
| 422 | no `audio_file`, or the file was rejected (`errors` lists why, e.g. not an accepted audio type) |
| 500 | anything else; `message` has the error |

```json
{ "success": false, "message": "Failed to save song", "errors": ["Audio file must be an audio file (mp3, m4a, mp4, ogg, flac, wav, aac)"] }
```

## Accepted formats

Content types `audio/mpeg`, `audio/mp3`, `audio/x-m4a`, `audio/mp4`, `audio/ogg`,
`audio/flac`, `audio/wav`, `audio/aac`.

## List songs

```bash
curl "http://localhost:3000/api/v1/songs?page=1&limit=50&search=beatles" \
  -H "Authorization: Bearer $API_TOKEN"
```
