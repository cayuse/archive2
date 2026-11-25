# Library repair and audio analysis tools

The one-off pipeline that repaired the archive's metadata and produced the radio data (Nov 2026).
These ran from a Windows PC with WSL (Debian) against a local staging copy of the database; paths
inside the scripts (`/mnt/c/Users/cayuse/ai_stuff/music_archive/...`) are that machine's and need
editing to run elsewhere. Credentials come from a `.env` next to `scripts/` (not in git):
`POSTGRES_*` for staging and `MB_*` for the MusicBrainz mirror.

Why the data needed repair: see `IMPORTER_ROOT_CAUSE.md`.

## Order of operations

| Step | Script | Output |
|---|---|---|
| 1. Local staging DB from a dump | `scripts/restore_staging.sh` | database `archive_staging` |
| 2. Run the app's Rails against staging | `scripts/rails.sh <cmd>` (image from `rails-dev/`) | migrations, rake tasks |
| 3. Read every file's tags (on the storage host) | `scripts/scan_tags.py` (same file as `archive/lib/tag_scanner/`) | `tags.jsonl` |
| 4. Load tags | `rails 'library:import_file_tags[tags.jsonl]'` | `song_file_tags` |
| 5. MusicBrainz lookups for the ids in the tags | `scripts/export_mbids.sql`, `scripts/mb_export_lookup.sql` | `lookup_{artist,release,recording}.tsv` |
| 6. Rebuild artists / albums / genres / credits | `rails 'library:rebuild[lookup_dir]'` (`DRY_RUN=1` to roll back) | repaired rows |
| 7. Audio analysis on a GPU | `scripts/analyze_audio.py` (loop: `run_analysis.ps1`) | `shard_*.npz`, `features.jsonl` |
| 8. Dials, sound-alike links, genre adjacency | `scripts/export_song_info.sql`, `scripts/build_vectors.py` | `out/*.tsv` |
| 9. Load audio data | `rails 'library:import_audio[out_dir]'` | features, neighbours, embeddings, genre affinities |

Checks: `scripts/root_cause.sql`, `scripts/post_rebuild_check.sql`, `scripts/smoke.rb` (renders the
pages with login bypassed), `scripts/radio_taste_test.rb` (genre modes), `scripts/jukebox_radio_test.rb`,
`scripts/station_engine_test.rb` (flow, repeats, per-station feedback, taste; asserts and rolls back),
`scripts/station_test.sh` (headless station against a mock OwnTone).

A Linux equivalent of the staging setup, with no machine-specific paths, is in `staging/`.

Audio model: `laion/larger_clap_music_and_speech` via `transformers==4.46.3`. Do not use
`laion/larger_clap_music`: its text side returns the same vector for every prompt.
