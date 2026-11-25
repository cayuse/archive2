# Importer repair: findings and proposed plan

Written 2026-11-24 for whoever repairs the importer on the server (it needs the local MusicBrainz
mirror, so it is being built there, not on the PC that did the data repair). Nothing in this file
has been implemented. File and line references are to branch `feature/library-metadata` at
`d988c7e`; paths are relative to `archive/` unless they start with `utilities/` or `library_tools/`.

Read first: `library_tools/IMPORTER_ROOT_CAUSE.md` (the measurements) and
`app/services/library_rebuilder.rb` (the rules the repaired data now follows).

## 1. The situation in one paragraph

The existing 74,687 songs have been repaired from the tags inside their files. That repair lives in
the dump described in `library_tools/RESTORE_ON_PRODUCTION.md`. **The importer itself is unchanged**,
so every song uploaded after the repaired database goes live is written the old, broken way. On
repaired data it is worse than before: the importer will attach a new song to whichever album row
happens to share its title, and there are now 137 separate "Greatest Hits" rows to pick from.
Until the importer is fixed, avoid bulk imports.

## 2. Findings

### 2.1 What the importer does wrong (measured; details in IMPORTER_ROOT_CAUSE.md)

| # | Fault | Where | Damage in the old data |
|---|---|---|---|
| 1 | `clean_string` turns every `-` and `_` into a space, on real tag values | `app/services/audio_file_processor.rb` (`clean_string`); same rule in `utilities/universal_upload.py` (`clean_string`) | 3,348 titles, 2,572 album titles, 191 artists, 94 genres altered |
| 2 | Only title, artist, album, genre and track are read | `audio_file_processor.rb` (`extract_metadata_with_ffprobe`) | No album had an artist or a date; disc numbers and MusicBrainz ids dropped |
| 3 | Albums are found or created by title alone | every `Album.find_or_create_by(title:)` below | 625 album rows each held several real releases (11,035 songs) |
| 4 | Tag keys matched in two spellings only (`album` / `ALBUM`) | same method | 1,058 FLAC songs lost album and genre (`Album`, `Genre`) |
| 5 | The find-or-create logic is copy-pasted | see 2.2 | Seven write paths to fix |
| 6 | Artists and genres keyed by exact name | same call sites | Split artists; "Hip Hop" vs "Hip-Hop" |
| 7 | Multi-value artist tags are flattened | ffprobe's view of the tags | Collaborations credited to one artist |

Ruled out: filename parsing overwriting tags. That fallback was removed (commit e1632c8) before the
big import; `extract_metadata_from_filename` and `parse_filename` are now dead code in the service.

### 2.2 Every place that writes artist / album / genre for a new song

| Path | Code | Notes |
|---|---|---|
| Background job | `app/jobs/audio_file_processing_job.rb` | Runs from `Song` `after_commit :schedule_processing` on create, and on update while status is pending / needs_review |
| Web upload | `app/controllers/upload_controller.rb:40`, `app/controllers/songs_controller.rb:116` | Call the job with `perform_now` |
| Web create and update | `app/controllers/songs_controller.rb:130-166` and `:244-280` | Inline copies; also invent "Unknown Album" / "Unknown Genre" rows |
| Web manual edit | `app/controllers/songs_controller.rb:344-382` | By-name find-or-create from form fields |
| API bulk upload | `app/controllers/api/v1/songs_controller.rb:166` (`bulk_upload`) | Two copies: from request params, then from file metadata. Used by `utilities/universal_upload.py` and `bulk_upload.py` |
| Bulk operations | `app/controllers/bulk_operations_controller.rb:138-149` | The only one that passes the artist to the album |
| Client scripts | `utilities/universal_upload.py`, `utilities/bulk_upload.py`, `utilities/import_tracker.py` | Linux tools. Parse the filename, apply their own `clean_string`, and send `title` / `artist_name` / `album_title` params that the API trusts over the file |

Related facts:
- `Song#extract_metadata_from_file` downloads the blob to a temp file and runs `AudioFileProcessor`
  on it. That is the single point where tags are read today.
- `Api::V1::SongsController` names `bulk_create`, `bulk_update`, `direct_upload` and
  `create_from_blob` in a `before_action` but does not define them. In development this raises
  (`raise_on_missing_callback_actions`); in production it is silent. Worth cleaning up in passing.
- The production image (`archive/Dockerfile`) has `ffmpeg` but no Python. The tag scanner needs
  `python3` and `python3-mutagen` (two Debian packages, no pip). `library_tools/rails-dev/Dockerfile`
  already installs them for the dev image.

### 2.3 What already exists to build on

| Piece | Where | State |
|---|---|---|
| Tag reader, one file | `lib/tag_scanner/scan_tags.py --file <path>` | Works. Prints one JSON object whose keys are the `song_file_tags` columns. Reads ID3, MP4 and Vorbis using Picard's tag names, case-insensitively, keeps multi-value artist ids, never raises on a bad file (sets `scan_error`) |
| Raw tags per song | table `song_file_tags`, model `SongFileTag` (`song.file_tag`) | Filled for all existing songs. Loader logic in `lib/tasks/library.rake` (`library:import_file_tags`), including the NUL-byte scrub Postgres needs |
| Target columns | `artists.musicbrainz_id` (unique), `albums.musicbrainz_release_id` (unique) plus release fields, `songs.disc_number / artist_credit / musicbrainz_recording_id`, table `song_artist_credits` | Migrated in the dump |
| The matching rules, as SQL | `app/services/library_rebuilder.rb` | Batch only: one transaction over the whole library, reads MusicBrainz from TSV files. Not usable per song as it stands, but it is the reference for behaviour |
| MusicBrainz queries | `library_tools/scripts/mb_export_lookup.sql` | The exact joins for artist, release and recording, including gid redirects |

### 2.4 The rules the repaired data follows (the importer must match these)

- **Values are never rewritten.** Trim whitespace, nothing else.
- **Artist:** by MusicBrainz artist id when the file has one (name, sort name, disambiguation and
  type taken from MusicBrainz, following redirects). Otherwise by name, case-insensitive; if that
  name belongs to exactly one existing MusicBrainz artist, use that row.
- **Album artist:** the album-artist tag (or its MusicBrainz id); "Various Artists" when the
  compilation flag is set and there is no album-artist tag; otherwise the song's artist.
- **Album:** by MusicBrainz release id when the file has one. Otherwise by
  album artist id + lower-cased title. Never by title alone.
- **Genre:** matched ignoring case and punctuation (`lower`, alphanumerics only), so "Hip Hop"
  and "Hip-Hop" are one row.
- **Song:** title, track, disc from tags; `artist_credit` is the artist tag as written;
  `musicbrainz_recording_id` after following redirects.
- **Credits:** one `song_artist_credits` row per MusicBrainz artist id in the file, in tag order;
  the main artist is position 0.
- **A tag value wins over what is in the database; where the file has no tag, the database value
  stays.** This keeps manual edits on untagged files.

## 3. Proposed plan

Ordered so each step is safe to ship on its own. Steps 1 and 2 stop the bleeding and need no
MusicBrainz access.

### Step 1. One service for all writes

Add `app/services/library_importer.rb` (name is a suggestion): given a song and its tag record, it
creates or finds the artist, album artist, album, genre and credits by the rules in 2.4 and updates
the song. Everything in table 2.2 calls it; the copies are deleted.

- Per-song Active Record code, not the batch SQL. Use the unique indexes plus
  `create_or_find_by` / rescue-and-retry for concurrent uploads of the same album.
- Model callbacks should run here (unlike the batch rebuild), so `SyncChange` rows are written and
  jukebox machines hear about new songs.
- Put the key functions (name key, genre key, album key) in one module and have tests assert they
  agree with `LibraryRebuilder`, so the importer and the batch rebuild cannot drift.
- Drop the "Unknown Album" / "Unknown Genre" placeholder rows; leave the link empty and set
  `needs_review`.

### Step 2. Read tags with the scanner, keep them

- Replace the ffprobe tag read in `AudioFileProcessor` with `scan_tags.py --file`. Keep ffprobe
  only for duration when the scanner reports none. Delete `clean_string`, `parse_filename` and the
  empty `extract_*_metadata` stubs.
- Add `python3 python3-mutagen` to the `apt-get install` line in `archive/Dockerfile`.
- Save the scanner output to `song_file_tags` for every new song, before deriving anything from it.
  A future importer bug can then be repaired from the database.
- Files with no usable tags: status `needs_review`, title from the original filename with the
  extension removed and nothing else changed. No pattern guessing.

### Step 3. MusicBrainz lookup at import time

Add a small read-only client for the mirror (bigballs, port 5433), used by the service when a file
carries MusicBrainz ids.

- Connection settings from environment variables, delivered the same way as the app's other
  secrets. If they are absent or the mirror is down, the import still succeeds using tag values and
  the song is marked so it can be enriched later. The mirror must never be required for an upload.
- Reuse the queries in `mb_export_lookup.sql`. Always look up by gid (index lookup) and follow the
  `*_gid_redirect` tables. Never scan a MusicBrainz table.
- Strictly read-only. `default_transaction_read_only=on` on the connection is a cheap guard
  (see `library_tools/scripts/psql_mb.sh`).
- Fills: artist name / sort name / disambiguation / type; album release group, type, status,
  country, label, catalogue number, barcode, disc and track totals, original year.

Not verified from here: whether the app container can reach port 5433 as deployed by Kamal. Check
that before designing around it.

### Step 4. Make the client scripts honest

In `utilities/universal_upload.py`, `bulk_upload.py` and `import_tracker.py`: stop parsing
filenames and stop sending `title` / `artist_name` / `album_title`. Upload the file and its original
filename; the server reads the tags. In `bulk_upload`, treat any metadata params that still arrive
as fallbacks used only where the file has no tag (today they win over the file).

### Step 5. Songs that need follow-up work

Uploads that arrive after the repair have no audio analysis, so they cannot be picked by radio or
seed a station. The agreed approach is that the server only flags them and the analysis runs later
on the GPU machine.

- A simple way to flag: "has no `song_audio_features` row" is already a complete definition, so no
  new column is needed. A rake task that lists those songs (id, blob key) is enough for the
  analysis scripts in `library_tools/scripts/` to pick up.
- Same idea for "imported while the mirror was unavailable": a task that re-runs step 3 for songs
  whose `song_file_tags` row has MusicBrainz ids that the song / album rows do not yet reflect.
- Later, optional: an AcoustID lookup for files with no MusicBrainz ids (7,937 existing songs on
  1,596 albums, mostly audiobooks).

### Step 6. Tests

No importer tests exist. Minimum set, using small fixture files or canned scanner JSON:

1. A title, album and genre containing `-` and `_` come through unchanged.
2. Two different artists each with an album called "Greatest Hits" produce two album rows.
3. Two songs with the same MusicBrainz release id land on one album even when their album-title
   tags differ.
4. A FLAC with keys spelled `Album` / `Genre` gets its album and genre.
5. A file with two artist ids produces two credits in order.
6. A compilation without an album-artist tag goes under "Various Artists".
7. A file with no tags becomes `needs_review` with no placeholder rows created.
8. The same file imported twice does not duplicate artist, album or genre rows.
9. Mirror unreachable: the import still completes from tags.

## 4. Things that will bite

- **Ordering.** The service needs the columns from the 12 migrations in the dump. Ship the importer
  after the repaired database and this branch are live, or in the same deploy, never before.
- **Replication.** `pub_archive` in the dump covers the original 15 tables, not `song_file_tags`,
  `song_artist_credits` or the radio tables. Decide whether jukebox machines need them before
  relying on them there.
- **Re-processing.** `Song` reschedules the job on update while a song is `needs_review`. Once the
  job writes richer data, make sure a manual edit to a `needs_review` song is not overwritten by
  the next run. The rule in 2.4 (tag wins, database kept where there is no tag) covers this only if
  manual edits to tagged files are treated as deliberate. That is a product decision to confirm
  with the owner.
- **Duplicates.** About 6,900 groups of byte-identical or same-recording files already exist. The
  blob checksum is available at upload time; refusing or flagging an exact duplicate is a cheap
  addition to step 1, but ask before making uploads fail.
- **Subprocess cost.** One Python start per file is fine for single uploads. For a bulk import of
  thousands, the scanner's batch mode (`scan_tags.py <songs.tsv> <out.jsonl> [workers]`) followed
  by `library:import_file_tags` is far faster than per-file calls.

## 5. Open questions for the owner

1. When someone edits a song by hand and the file's tags disagree, which wins on the next re-scan?
2. Should an exact duplicate upload be refused, flagged, or accepted?
3. Should the app ever write corrected tags back into the audio files? Everything above assumes no:
   files are read-only.
