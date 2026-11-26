# Song processing

What happens to an audio file between upload and being a tagged song in the library:
upload, reading the file's tags, the processing status, and the Maintenance page where a
moderator fixes what the tags could not fill in.

This covers the basic tags only (title, artist, album, genre, track, duration). The deeper
analysis that radio depends on (audio features, embeddings, neighbours, MusicBrainz ids) is
done by separate tools: see `../../library_tools/README.md`.

## Processing statuses

`songs.processing_status` (a string; errors go in `songs.processing_error`):

| Status | Meaning | Set by |
|---|---|---|
| `needs_review` | Uploaded; the song lacks a title or an artist. | upload, the processing job |
| `processing` | The job is reading the file right now. | the processing job |
| `completed` | The song has a title and an artist. | the processing job, or any save (see below) |
| `failed` | Reading the file raised an error; the message is in `processing_error`. | the processing job, the edit page, a retry |
| `pending` | A failed song being retried (momentary). | `SongsController#update` |

"Complete" means only **title and artist are present** (`Song#has_complete_metadata?`).
Album and genre are optional. A `before_save` callback moves any `needs_review` song with
both to `completed`, so filling in the artist on the edit page is enough.

The model also accepts `new`, and the views have a badge for it, but nothing sets it.
A song created by CSV import has no status at all.

## How a file gets in

### Web upload

Moderators and admins (`SongPolicy#upload?`). "Upload Song" in the navigation bar.

1. `GET /upload` — a form with one field, the audio file.
2. `POST /upload` (`UploadController#create`) — creates the song with the file attached,
   status `needs_review`, the uploader as `user`, the original file name in
   `original_filename`, and the file name (minus extension) as a provisional title.
3. The file's tags are read (see below).
4. Redirect to `GET /songs/:id/edit`, where the uploader checks the result, picks or types
   the artist, album and genre, and saves (`PATCH /songs/:id`).

### API upload

`POST /api/v1/songs/bulk_upload`, one file per request, moderator or admin token. The tags
are read inside the request by the controller itself (not by the job), and only fill in what
the request's own parameters left blank. `skip_post_processing=true` skips reading tags.
See `BULK_OPERATIONS_AND_API.md` and `archive_api.md`.

### CSV import

`/bulk_operations` creates song records with no audio file. Nothing is processed.

## Accepted files

The attachment's content type must be one of `audio/mpeg`, `audio/mp3`, `audio/x-m4a`,
`audio/mp4`, `audio/ogg`, `audio/flac`, `audio/wav`, `audio/aac`. `file_format` is one of
`mp3 m4a mp4 ogg flac wav aac`. Files are stored with Active Storage's local disk service (`archive/storage`, which is
`/rails/storage` in the container).

## Reading the tags

`AudioFileProcessingJob` → `Song#extract_metadata_from_file` → `AudioFileProcessor`.

The song's file is copied to a temp file and `ffprobe` (from the `ffmpeg` package in the
Docker image) is run on it twice: once for the format tags, once for the duration. From the
tags it takes `title`, `artist`, `album`, `genre` and `track` / `tracknumber` (the part
before any `/`), plus the duration rounded to seconds, the format (from the content type)
and the file size.

The job then:

- overwrites the song's title, track number, duration, format and size with whatever was found;
- finds or creates the `Artist` by name, the `Album` by title and the `Genre` by name, and sets them;
- sets the status to `completed` if the song now has a title and an artist, otherwise `needs_review`;
- on an exception, sets `failed` and stores the message.

The job does nothing if the song has no file, or is already `processing` or `completed`.

There is no fallback to parsing the file name: `AudioFileProcessor` contains a file-name
parser, but nothing calls it. A file with no tags simply stays `needs_review` with its
provisional title.

### When the job runs

Controlled by `INLINE_AUDIO_PROCESSING` (default `true`, and `true` in production):

- `true` — `UploadController` runs the job inside the upload request, so the edit page
  already shows the tags. The model does not enqueue anything.
- `false` — the model enqueues the job after a song is created, and again after an update
  while the song has a file and is still unprocessed (blank status, `pending`, `needs_review`, or
  `failed` with no error). Active Job's adapter is `:inline` in development and in
  production (`USE_SIDEKIQ=false`), so the job still runs in the request.

## The edit page and retry

`GET /songs/:id/edit`, moderators and admins.

- If the song has a file and no status yet, the tags are read on the spot and saved; when
  the file has no album or genre tag the song is put in "Unknown Album" / "Unknown Genre".
- A `failed` song has a "Retry Processing" button on its own page (`/songs/:id`; it sends
  `PATCH /songs/:id?retry_processing=true`), which reads the tags again the same way and
  returns to the edit page.
- Artist, album and genre are picked with autocomplete (`/artists/search`, `/albums/search`,
  `/genres/search`) or typed as new names.

Deleting a song (`DELETE /songs/:id`) is admin only.

## Maintenance page

`GET /songs/maintenance`, moderators and admins; "Maintenance" in the navigation bar.

A paged list of songs filtered by status: **Needs Review** (the default), **Failed** or
**All** (`?status=needs_review|failed|all`; any other status value works in the URL). Each
row shows the original file name, status and error, with Edit and (for admins) Delete.

There are no multi-select or bulk actions on this page. `POST /songs/bulk_update` is routed
but no page uses it.
