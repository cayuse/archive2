# Why the archive's metadata is wrong: importer root causes

Measured 2026-11-24 on the staging copy by comparing every song's database values with the tags
embedded in its file (`song_file_tags`, 74,687 rows, 1 unreadable file). Rerun with
`scripts/root_cause.sql`. App code referenced is `archive/` at commit 6b88677.

The files are in good shape: 99.6% have a title tag, 91% an album-artist tag, 95% a date,
89% MusicBrainz recording and release IDs. The damage was done on the way into the database.

## Causes, with measured damage

| # | Cause | Where | Damage |
|---|---|---|---|
| 1 | `clean_string` replaces every `-` and `_` with a space, on values read from tags | `app/services/audio_file_processor.rb:179`; same rule in `utilities/universal_upload.py:373` | 3,348 titles, 2,572 album titles, 191 artist names, 94 genres altered ("1-2-8" became "1 2 8", "Hip-Hop" became "Hip Hop") |
| 2 | Only five tags are read: title, artist, album, genre, track | `audio_file_processor.rb:52-61` | All 12,088 albums have no artist and no date, although 68,059 songs carry an album-artist tag and 71,302 a date. Disc numbers and MusicBrainz IDs are dropped too. |
| 3 | Albums are found or created by title alone | `Album.find_or_create_by(title:)` in the job and controllers | 625 album rows hold more than one real release, covering 11,035 songs. "Greatest Hits" is one row holding 133 releases by 121 artists. |
| 4 | Tag names are matched in two spellings only (`album` / `ALBUM`) | `audio_file_processor.rb:52-58` | 1,058 FLAC songs have no album and no genre because their files spell the keys `Album` and `Genre`. Vorbis comment names are case-insensitive. |
| 5 | The find-or-create logic is copy-pasted | `audio_file_processing_job.rb`, `songs_controller.rb` (3 places), `api/v1/songs_controller.rb` (2), `bulk_operations_controller.rb` | Seven write paths that each need the same fix. Only `bulk_operations_controller` passes the artist when creating an album. |
| 6 | Artists and genres are keyed by exact name | same call sites | Minor: 7 MusicBrainz artists are split over 14 rows. Case and spelling variants in genres. |

Not a cause (earlier belief, now ruled out): filename parsing overwriting tag data. That fallback
was removed in commit e1632c8 on 2025-08-21, minutes before the 71,830-song bulk import began.
Only 17 songs have a filename-derived title where a tag existed, and 276 songs with no title tag
got a title from somewhere else (manual edits or the filename).

Smaller findings:
- 6 artists stored as "Aerosmith" where the file holds two artist values; multi-value tags are not handled.
- 69 songs have a genre that matches neither the tag nor its cleaned form (for example a year), and
  59 songs have an artist with no tag behind it. These look like manual edits or older import runs.

## What a repaired importer needs

1. One service that turns file metadata into Song / Artist / Album / Genre records, called from
   every upload path. Delete the six copies.
2. No rewriting of tag values. Trim whitespace only. Filename parsing is a last resort for files
   with no tags, and its output is marked for review.
3. Read the full tag set, case-insensitively: album artist, date, original date, disc number and
   total, track total, compilation flag, MusicBrainz IDs, sort names. A tag library reads these
   more reliably than `ffprobe`'s flattened view.
4. Key albums by MusicBrainz release ID when present, otherwise by album artist plus title.
   Key artists by MusicBrainz artist ID when present, otherwise by name.
5. Keep the raw tags per song (`song_file_tags` does this) so a future bug can be repaired from
   the database without rereading 433 GB.
