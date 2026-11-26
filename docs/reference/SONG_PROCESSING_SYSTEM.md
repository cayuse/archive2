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

### The Drop Box

The way in for people: `/intake` ("Drop Box" in the navigation bar; moderators and admins,
`SongPolicy#upload?`). It takes files, folders and archives, identifies them against MusicBrainz,
rewrites their tags and files them. See `INTAKE.md`. `GET /upload` redirects there.

The rest of this document is about the older per-song job, which the API upload and the
Maintenance page still use. It reads tags and files the song by them (`TagScanner`,
`LibraryImporter`) but does not consult MusicBrainz or change the file.

### When the job runs

Controlled by `INLINE_AUDIO_PROCESSING` (default `true`, and `true` in production):

- `true` — the model does not enqueue anything; callers run the job themselves.
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
