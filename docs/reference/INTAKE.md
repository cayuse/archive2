# The Drop Box (intake)

How music gets into The Archive. One page (`/intake`, "Drop Box" in the navigation; moderators and
admins) takes dropped files, whole folders with subfolders, and archives. A worker then deals with
every file and the page shows what became of each.

## What happens to a drop

1. **Sending.** The browser walks what was dropped and sends each file with its path inside the
   folder (`IntakeController`, `public/javascripts/intake/intake.js`). Files land in
   `incoming/<batch>/`. Operating-system clutter (`.DS_Store`, `Thumbs.db`) is not sent. The limit
   per file is nginx's `client_max_body_size` (500 MB on bigballs).
2. **Unpacking.** zip, tar (and .gz/.bz2/.xz/.zst), 7z and rar are unpacked with `bsdtar`, up to
   three levels deep. Absolute paths, `..` and links cannot write or read outside the drop; an
   archive of more than 20,000 entries or 50 GB is refused.
3. **Sorting.** A file is music only if its extension is one the library takes (mp3, flac, m4a,
   mp4, ogg, oga, opus, wav, aac) *and* `ffprobe` finds an audio stream in it. Everything else is
   "set aside": listed with the reason, never imported.
4. **Duplicates.** Identical bytes to a stored file, or to a file as it was first dropped, is
   "already here". So is a track of a release the library already holds (same MusicBrainz
   recording and release), and the same file twice in one drop.
5. **Identifying** (`MusicbrainzMatcher`, against the local mirror via `MusicbrainzMirror`). The
   files of one folder that name the same album are compared track by track (title, length) with
   every release of that name by that artist; the best-fitting release wins if at least 80% of
   the files fit. That picks the right pressing. A file that fits no release is matched alone by
   artist, title and length. Files that carry MusicBrainz ids are checked against those ids.
   Nothing found: the file is filed under its own tags and the page says "Not in MusicBrainz".
6. **Tagging** (`TagWriter`, `lib/tag_scanner/write_tags.py`). The file's tags are replaced with
   one standard layout, the one MusicBrainz Picard writes: ID3v2.4 for mp3 (ID3v1 and APE blocks
   removed), Vorbis comments for flac/ogg/opus, iTunes atoms for m4a. MusicBrainz's values where
   the file was identified, the file's own otherwise; genre, composer and language always stay
   the file's. Pictures, lyrics and ReplayGain are kept; everything else the ripper left is
   dropped. The decoded audio is hashed before and after: if it differs, or anything fails, the
   original file is restored and stored as it arrived. wav and aac are not rewritten.
7. **Filing** (`LibraryImporter`). The file is stored, its tags recorded in `song_file_tags`, and
   the song, artist, album, genre and credits created or found by the rules in that class.

The untouched original of every imported file, and every archive, is kept in
`originals/<batch>/` for 30 days, then removed by the worker.

## The pieces

| Piece | Where |
|---|---|
| Page and upload endpoints | `IntakeController`, `app/views/intake/`, `public/javascripts/intake/intake.js` |
| A drop and its files | `IntakeBatch`, `IntakeItem` (tables `intake_batches`, `intake_items`) |
| Disk layout and limits | `Intake` (`INTAKE_ROOT`; production `/datatank/archive/intake`) |
| The pipeline | `IntakeProcessor` |
| The worker | `rake intake:work` (Kamal role `intake`); `rake intake:run` deals with what is waiting and stops |
| Dropping from the server's own disk | `rake "intake:drop[/path/to/folder,user@example.com]"` |

Only one worker runs at a time (a Postgres advisory lock). Stopping it mid-drop is safe: the next
worker carries on from what is left in `work/<batch>/`.

MusicBrainz is optional by design: with `MUSICBRAINZ_URL` unset or the mirror down, files are
filed under their own tags. The login is a read-only role (`archive_mb_ro`) on the mirror.

## The analysis reserve

New songs have no sound analysis, so stations cannot pick them. `Song.awaiting_analysis` is the
reserve; the Drop Box page shows its size. Pulling those files to the analysis PC and loading the
results back is not built yet (see `STATUS.md`).

## Not built

- Fingerprint lookup (AcoustID) for files with no usable tags. The fingerprints are not in
  MusicBrainz; it needs AcoustID's web service and a key, or a local copy of their database.
- A watched folder on the server (SMB share) as a second way in. `intake:drop` covers it by hand.
- Files over 500 MB (would need chunked sending).
- Replacing a stored song with a better copy (an mp3 the library has, dropped again as flac, is
  reported as "already here").
