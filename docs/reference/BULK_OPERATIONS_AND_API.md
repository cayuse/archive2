# Bulk operations and bulk upload

Three ways to work on many songs at once:

1. the **Bulk Operations page** (`/bulk_operations`): CSV export, delete by id;
2. the **upload API** (`POST /api/v1/songs/bulk_upload`) and the scripts in `utilities/` that drive it;
3. the **Maintenance page** (`/songs/maintenance`) for songs whose tags need attention — see `SONG_PROCESSING_SYSTEM.md`.

The full API is in `archive_api.md`.

## Bulk Operations page

`/bulk_operations`, moderators and admins only (`BulkOperationsController`). It is not in the
navigation bar; open it by URL. The page also shows counts of songs, artists, albums and genres.

### CSV export

`GET /bulk_operations/export_csv` downloads `songs_export_<date>.csv` with every song:

```
id,title,track_number,duration,file_format,file_size,artist_name,album_title,album_release_date,genre_name,created_at,updated_at
```

The export has the import's columns plus `id`, `created_at` and `updated_at`. It is not a
round trip: importing an export creates new songs rather than updating the exported ones.

### Bulk delete

`POST /bulk_operations/bulk_delete`, form field `song_ids`: song ids (UUIDs, e.g. the `id`
column of the export) separated by commas, spaces or new lines. Each song found is destroyed
together with its audio file. Anything that is not a UUID, and any id with no song, is
reported back; the rest are still deleted.

## Uploading audio files in bulk

There is one upload endpoint. It takes one file per request:

```bash
# 1. log in (moderator or admin)
curl -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "you@example.com", "password": "…"}'
# → { "success": true, "api_token": "…", "expires_at": …, "user": { … } }

# 2. upload a file
curl -X POST http://localhost:3000/api/v1/songs/bulk_upload \
  -H "Authorization: Bearer $API_TOKEN" \
  -F "audio_file=@/path/to/song.mp3"
```

Optional form fields: `filename`, `title`, `artist_name`, `album_title`, `genre_name`,
`track_number`, `duration`, `skip_post_processing=true`. What happens to the file after that
is described in `SONG_PROCESSING_SYSTEM.md`.

To upload a directory tree, use the scripts in `utilities/` (see `utilities/README.md`).
Both log in, walk the directory and call `bulk_upload` once per file, recording progress in
a SQLite file so an interrupted run can be resumed:

```bash
python3 utilities/bulk_upload.py ~/Music --url https://archive.example --username you@example.com --verbose
python3 utilities/universal_upload.py ~/Music --url https://archive.example --username you@example.com --concurrent 5
```

`bulk_upload.py` uploads one file at a time; `universal_upload.py` uploads several at once
and is more careful with odd file names.

The token lasts 2 days by default; pass `expires_in` (seconds, up to 30 days) to `login`
for a long run, or call `POST /api/v1/auth/refresh`.

## What does not exist

Earlier versions of this document listed endpoints that were never built or have been
removed: `songs/bulk_create`, `songs/bulk_update`, `songs/bulk_destroy`, `songs/export`,
`songs/direct_upload`, `songs/create_from_blob`, and `/api/v1/search`. To search, use the
`search` parameter of `GET /api/v1/songs`. To change many songs, use the web pages.
