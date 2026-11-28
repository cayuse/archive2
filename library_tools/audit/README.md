# Library audit

Finds broken files, low-fidelity copies and duplicates across the whole archive. It uses standard
signal checks only, with no AI. It is in two steps, so the rules can be tuned without decoding
anything again:

1. **`scan.py` measures.** It reads every stored file and records raw numbers in a SQLite results
   file. A full pass over about 75,000 files takes roughly 9 hours on gameforge with 15 workers.
2. **`score.py` judges.** It turns the numbers into verdicts, scores and duplicate groups and writes
   CSV reports. It takes about a minute, so change `RULES` and run it again as often as needed.

The measuring and judging code is shared with the app: `archive/lib/audio_audit` (`measure.py`,
`judge.py`, `textnorm.py`); the Drop Box runs the same checks on every file it takes in
(`docs/reference/LIBRARY_QUALITY.md`). `export_measurements.py` turns a results file into what
`rake "library:load_audit[FILE]"` loads into `song_measurements`.

Nothing here writes to production. The song list comes from the read-only `archive_clone` role, and
files are read over SSH (`cat`) into a scratch directory that is emptied as it goes. Deleting or
replacing anything is a separate, reviewed step.

## Running it

```bash
cd library_tools/audit
./export_songs.sh                                   # ~/archive-audit/songs.csv from production (read only)
AUDIT_DB=sample.sqlite ./run_scan.sh --sample 500   # a test batch: the same 500 files every time (--seed)
AUDIT_DB=results.sqlite ./run_scan.sh --workers 15  # everything; Ctrl-C stops, running it again resumes
docker run --rm -v ~/archive-audit:/data -v "$(git rev-parse --show-toplevel)":/repo:ro archive-audit:local \
  python3 -I /repo/library_tools/audit/score.py --songs /data/songs.csv --out /data/report /data/results.sqlite
docker run --rm -v ~/archive-audit:/data -v "$(git rev-parse --show-toplevel)":/repo:ro archive-audit:local \
  python3 -I /repo/library_tools/audit/export_measurements.py --songs /data/songs.csv --out /data/measurements.copy /data/results.sqlite
```

- **Resume.** Files already measured with the current `MEASURE_VERSION` are skipped. Raise the
  version when a measurement changes; the next run then re-measures only what is older.
  `--retry-failed` re-reads files that could not be read before.
- **Spread.** `--shard i/n` takes one part of the library, so several machines can each run a part.
  On bigballs itself, use `AUDIT_SOURCE=local:/datatank/archive/psql_storage`. `score.py` accepts
  any number of result files.
- **Load.** `run_scan.sh` caps the container at `AUDIT_CPUS` (15 by default, about 75% of gameforge)
  and runs the workers at lower priority, so a game or a Jellyfin stream still comes first.

## What is measured (`scan.py`)

| | |
|---|---|
| integrity | checksum against the database; a strict ffmpeg decode (error count only, since strict mode drops the frames it doubts); a normal decode's errors; `mp3val` frame structure; `flac -t` (FLAC's own checksum of every sample) |
| damage | bursts far past full scale (corrupt frames blow up into loud pops); digital silence in the middle of the music; level jumps; clicks; how loud the last instant is (cut-off files) |
| quality | EBU R128 loudness and true peak, clipping, DC offset, stereo correlation, and the spectrum in 250 Hz bands. An encoder's lowpass shows where the file really stops |
| identity | Chromaprint fingerprint of the first 120 s (what AcoustID uses). It is also a damage probe: `fpcalc` gives up at the first undecodable frame |

## Verdicts (`score.py`)

| verdict | meaning | examples |
|---|---|---|
| `bad` | broken in a way you hear, or unreadable: replace | loud blowouts, corrupt data mid-song, dropouts, truncated, silent, checksum mismatch |
| `flawed` | plays, but has a fault | a few damaged frames, channels out of phase, a "lossless" file made from a lossy one, cut off at the end |
| `weak` | intact, but low fidelity | low bitrate, or a sharp cutoff well below what the bitrate should carry |
| `ok` | | |

`notes` list things that never change the verdict: junk after the last frame, a heavily clipped
master, a strict decoder's complaints that players ignore, a wrong MP3 length header (fixable
without re-encoding), mono stored as stereo.

The things learned from real files while tuning:

- Strict-mode decode errors are noise. Thousands of them appear on perfectly good files from some
  encoders, so they never decide a verdict.
- Damage blowouts last 4–30 ms and reach 1.6–6× full scale, 2–3× the music around them. A hot
  master's overshoots last under 1 ms and stay around 1.3×.
- A lossy encoder's lowpass falls 30–70 dB within about 1.5 kHz. Natural roll-off (old recordings)
  falls 2–15 dB. Only the sharp kind counts.
- Many 192k MP3s stop at about 16 kHz, a mark of old encoders as much as of conversions. They are
  `weak`, not `flawed`.

## Duplicates

The same recording is found by fingerprint. On a test set of 80 same-title groups:
- Same recordings (exact copies, remasters, compilation copies) had a bit error rate of 0.00–0.20.
- Different recordings (live versions, re-recordings) had 0.30–0.50.
- The cutoff is 0.20. Lengths must agree within max(4 s, 3%); otherwise it is listed as a different
  edit and not merged.
- Recall was 106 of 110 true pairs, with no wrong merges.

The kept copy is chosen by fixed rules, in order:
1. intact beats `weak` beats `flawed` beats `bad`;
2. real lossless;
3. where the music really stops (anything from 19.5 kHz up counts as equal);
4. bitrate tier;
5. the artist's own album over a hits package or a compilation;
6. bitrate;
7. plays.

## Other tools

- `incoming.py`: judges a folder of new music against the library without importing it (new /
  better / not better), the same decision the Drop Box makes.
- `lidarr_push.py`: adds the artists behind broken songs to Lidarr (studio albums, the "Archive"
  quality profile) and queues the albums that hold broken songs first. Needs
  `~/.config/archive/lidarr.env`.

## Reports

In `--out`:
- `summary.txt`: the counts.
- `files.csv`: every file with its verdict, quality 0–100, problems and notes.
- `replace.csv`: songs whose best copy is `bad` (replace), `flawed` (upgrade) or `weak` (low
  fidelity).
- `duplicates.csv`: each group with its keep / drop decision and the reason.

Dropping a duplicate also drops that song row's place on its album (a compilation, for example).
Decide that when the clean-up is built.
