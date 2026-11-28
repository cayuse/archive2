# Library quality

How The Archive keeps one good playing copy of each recording without ever deleting a file, and how
music that arrives is judged before it counts. The rules come from the library audit of November 2026
(`library_tools/audit/README.md`), which measured all 74,724 stored files.

## Every file is measured

`lib/audio_audit` (Python: ffmpeg, mp3val, flac, fpcalc, numpy, scipy) measures a file and judges it.
The same code measured the whole library, so every number compares directly.

| | |
|---|---|
| verdict | `ok`, `weak` (intact, low fidelity), `flawed` (plays, with a fault), `bad` (broken: blowouts, corrupt frames, dropouts, truncated, silent) |
| quality | `codec`, `kbps`, `lossless` (real lossless; a FLAC made from an MP3 counts as lossy), `bits` and `sample_rate` for lossless, `eff_khz` (where the music really stops), loudness |
| identity | the Chromaprint fingerprint of the first 120 s (what AcoustID uses), raw and as sampled values with a GIN index |

Each song has at most one `SongMeasurement`. The Drop Box measures every file it takes in
(`AudioAudit`); the rest of the library was loaded from the audit (`rake "library:load_audit[FILE]"`,
fed by `library_tools/audit/export_measurements.py`), which also recorded each song's quality issue.

## Copies of one recording

Two files are the same recording when their fingerprints, slid against each other, differ in at most
20% of their bits, and their lengths agree within 3% (or 4 s). In this library, copies of a recording
measure 0.00–0.20 and different recordings (live, re-recorded) 0.30–0.50. A different length is a
different version (radio edit, extended mix) and is never merged. `Fingerprint.matches` finds them: the
index proposes songs sharing sampled values, songs of the same title are always proposed too (remasters
can share almost no exact values), and every proposal is checked bit by bit. On the real library it
found 171 of 180 copies the audit had grouped and nothing it had not; the misses are 7-second chant
clips and one copy linked only through a third.

Which copy plays (`CopyRanking`, the same order as `judge.py strength_of`):

1. intact beats weak beats flawed beats bad
2. real lossless beats lossy
3. hi-res beats CD (24-bit / 48 kHz over 16-bit / 44.1 kHz)
4. where the music really stops, to the half kHz (19.5 kHz and up count as equal)
5. bitrate tier: 256+, 192+, 128+, below
6. the artist's own album over a hits package or compilation (named in several languages)
7. bitrate, then plays

A new copy takes over only when it wins on 1–5. Below that the copy already there stays, so a
re-release does not flip the library back and forth.

## Hidden, never deleted

`SongMerger#merge` runs on each new song. The losing copy is hidden: `songs.canonical_song_id` points
at the copy that plays. A hidden copy keeps its file, its tags, its analysis and its history.

- Lists, search, stations and the analysis reserve show live songs only (`Song.live`).
- Album pages keep the whole tracklist; a hidden track says which copy it plays as.
- Anything that plays or queues a hidden copy by id gets the copy that plays (`Song#playable_song`,
  `Song.playable_ids`, `AjbQueueItem`), so an old link or a phone's cached queue never plays the old file.
- Playlists: the slot moves to the survivor in the same place. When the survivor is already on that
  playlist, it keeps the earlier of the two places and the playlist holds it once.
- Queued plays and station votes move with the song, except a thumbs-down on a copy hidden as broken,
  which was most likely about the damage (`SongMerger::CARRY_DOWN_FROM_BROKEN`).
- No chains: copies hidden onto a copy that is later replaced point at the newest.

Every row a merge changes is logged in `song_merges.moves`. **Library quality** (`/library/quality`,
admins) lists the merges with a Restore button that puts each row back and makes the copy play again,
and the wanted list: songs whose only playing copy is broken, flawed or low fidelity, most played first.

`song_issues` keeps the reasons, several per song: `broken`, `flawed`, `low_fidelity` (from the
measurement), `superseded` (a better copy arrived) and `duplicate` (arrived second, not better). A
quality issue is resolved when the song is replaced, so a song can be both "was broken" and "superseded".

## Where music comes from

All of it goes through the Drop Box (`INTAKE.md`), so all of it is measured, identified against the
MusicBrainz mirror, retagged in Picard's layout, and merged:

- the Drop Box page;
- Lidarr's root folder, `/datatank/lidarr` (watched as `lidarr`);
- the drop folder, `/datatank/downloads/music` on the Samba share (watched as `drop`): purchases and
  anything else, in any layout.

Nothing asks for approval: getting it into Lidarr or the drop folder is the decision. The safety is in
the rules above and the way back.

## Not built yet

- Applying the audit's duplicate groups to the existing library (hiding its 12,740 extra copies). The
  library is cleaned as better copies arrive; a one-off pass is a separate decision.
- Telling Lidarr that a download was broken, so it blocks that release and searches again.
- Feeding Lidarr's wanted list in tiers from `SongIssue.wanted` (`library_tools/audit/lidarr_push.py`
  did the first, broken, tier by hand on 2026-11-28).
