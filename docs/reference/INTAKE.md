# The Drop Box (intake)

How music gets into The Archive. One page (`/intake`, "Drop Box" in the navigation; moderators and
admins) takes dropped files, whole folders with subfolders, and archives; the worker also takes music
from watched folders by itself (below). It deals with every file and the page shows what became of each.

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
   "already here", and so is the same file twice in one drop. Anything else is taken in: whether it
   is another copy of a song the library has is decided by its sound at step 8, not by its tags.
5. **Measuring** (`AudioAudit`, `lib/audio_audit`): verdict, quality and fingerprint, the checks the
   whole library was audited with (`LIBRARY_QUALITY.md`).
6. **Identifying** (`MusicbrainzMatcher`, against the local mirror via `MusicbrainzMirror`). The
   files of one folder that name the same album are compared track by track (title, length) with
   every release of that name by that artist; the best-fitting release wins if at least 80% of
   the files fit. That picks the right pressing. A file that fits no release is matched alone by
   artist, title and length. Files that carry MusicBrainz ids are checked against those ids. A
   file still unplaced is looked up by its sound through AcoustID when `ACOUSTID_KEY` is set
   (`AcoustidClient`; only the fingerprint and length are sent). Nothing found: the file is filed
   under its own tags and the page says "Not in MusicBrainz".
7. **Tagging** (`TagWriter`, `lib/tag_scanner/write_tags.py`). The file's tags are replaced with
   one standard layout, the one MusicBrainz Picard writes: ID3v2.4 for mp3 (ID3v1 and APE blocks
   removed), Vorbis comments for flac/ogg/opus, iTunes atoms for m4a. MusicBrainz's values where
   the file was identified, the file's own otherwise; genre, composer and language always stay
   the file's. Pictures, lyrics and ReplayGain are kept; everything else the ripper left is
   dropped. The decoded audio is hashed before and after: if it differs, or anything fails, the
   original file is restored and stored as it arrived. wav and aac are not rewritten.
8. **Filing and merging** (`LibraryImporter`). The file is stored, its tags recorded in `song_file_tags`, and
   the song, artist, album, genre and credits created or found by the rules in that class. Its
   measurement is kept, and `SongMerger` compares it with the library's copies of the same recording:
   **Added** (new), **Upgrade** (better: the old copies now play as this one) or **Kept, hidden** (not
   better). Nothing is deleted; see `LIBRARY_QUALITY.md`.

The untouched original of every imported file, and every archive, is kept in
`originals/<batch>/` for 30 days, then removed by the worker. Not for a watched folder: the folder
itself is the original.

## Watched folders

`INTAKE_WATCH` names folders the worker looks at every minute (`IntakeWatcher`), mounted read-only:

| name | production | what |
|---|---|---|
| `lidarr` | `/datatank/lidarr` | Lidarr's root folder: Artist / Album (Year) / tracks |
| `drop` | `/datatank/downloads/music` (Samba `downloads/music`) | anything else, in any layout |

A unit (in `lidarr` an Artist/Album folder; in `drop` each top folder, and the loose files together)
becomes one batch once nothing in it has changed for 5 minutes. Audio files and archives are copied;
hidden files, Mac `._` files and partial downloads are skipped, other files are not taken. Each file
is taken once (`intake_watch_files`) and again only when its size or time changes, as when Lidarr
replaces a file with an upgrade. The watched folders are never written to. Batches are filed under
`INTAKE_WATCH_USER` (an email) or the first admin.

## The pieces

| Piece | Where |
|---|---|
| Page and upload endpoints | `IntakeController`, `app/views/intake/`, `public/javascripts/intake/intake.js` |
| A drop and its files | `IntakeBatch`, `IntakeItem` (tables `intake_batches`, `intake_items`) |
| Disk layout and limits | `Intake` (`INTAKE_ROOT`; production `/datatank/archive/intake`) |
| The pipeline | `IntakeProcessor` |
| The worker | `rake intake:work` (Kamal role `intake`); `rake intake:run` deals with what is waiting and stops |
| Watched folders | `IntakeWatcher`, `IntakeWatchFile`; `rake intake:watch` looks once |
| Measuring, merging | `AudioAudit` (`lib/audio_audit`), `SongMerger`, `CopyRanking`, `Fingerprint` (`LIBRARY_QUALITY.md`) |
| Dropping from the server's own disk | `rake "intake:drop[/path/to/folder,user@example.com]"` |

Only one worker runs at a time (a Postgres advisory lock). Stopping it mid-drop is safe: the next
worker carries on from what is left in `work/<batch>/`.

MusicBrainz is optional by design: with `MUSICBRAINZ_URL` unset or the mirror down, files are
filed under their own tags. The login is a read-only role (`archive_mb_ro`) on the mirror.

## The analysis reserve

New songs have no sound analysis, so stations cannot pick them. `Song.awaiting_analysis` is the
reserve; the Drop Box page shows its size. An outside machine works through it with the analysis API
(`ANALYSIS_API.md`).

## Not built

- Files over 500 MB from the page (would need chunked sending; a watched folder has no limit).
