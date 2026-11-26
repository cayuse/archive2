# Generating the sample songs

Instructions for an AI music generator (written for Grok, but nothing here is specific to it).
Work in the folder that contains this file.

## The job

Generate one short, original song for every line of `song_prompts.jsonl` (609 lines) and save
each as an MP3 in the `clips/` folder next to this file. These are stand-in audio for a music
library's development database, so they need to sound like real, varied music, not be
masterpieces.

Each line of `song_prompts.jsonl` is one JSON object:

```json
{"file":"ad609c37-ec3d-4111-841a-3ae069e6f4d8.mp3","seconds":30,"genre":"Rock/Pop","bpm":156,"vocals":"sung","prompt":"30 seconds of an original Rock/Pop piece, about 156 BPM. Happy, uplifting mood, soft and tender, acoustic instruments. A lead vocal singing original made-up lyrics. Entirely new: do not imitate any existing song, melody, lyrics or artist."}
```

| Field | Meaning |
|---|---|
| `file` | The exact file name to save as, inside `clips/`. Do not rename it: the name is how the song is matched. |
| `seconds` | Target length, 15 to 30. |
| `genre` | Style to write in. `null` means any style that fits the prompt. |
| `bpm` | Target tempo. |
| `vocals` | `sung`, `rapped`, `instrumental` (no voice at all) or `spoken` (a person talking, little or no music). |
| `prompt` | The full request in words. It already includes everything above; use it as the generation prompt. |

## Rules

1. **One file per line**, saved as `clips/<file>`, MP3, 44.1 kHz, 128 kbps or better, stereo or mono.
2. **Never longer than 30 seconds.** Aim for `seconds`; a second or two short is fine. If the
   generator can only make longer audio, cut it to `seconds` and fade out the last second.
3. **Everything must be original.** Write new lyrics for each sung, rapped or spoken piece. Do not
   imitate, quote, cover or name any existing song, melody, lyric, artist or band, and do not
   clone any real person's voice. The genre names describe a style only.
4. **Follow the tempo and mood.** Two songs of the same genre should still sound different when
   their prompts differ (fast and aggressive against slow and tender, sung against instrumental).
5. **Resumable.** Before generating a line, skip it if `clips/<file>` already exists and is not
   empty. Work top to bottom so a stopped run can be continued by running it again.
6. **Failures.** If a line cannot be generated after two tries, append it to `failed.jsonl`
   (same folder, same JSON plus an `"error"` field) and move on. Do not stop the run.
7. **Touch nothing else.** Only create files in `clips/` and `failed.jsonl`. Do not edit
   `song_prompts.jsonl` or anything outside this folder.
8. **Report** every 50 songs: how many are done, skipped and failed. At the end, give the totals.

## A smaller job first (optional)

`clips.json` describes 31 songs instead of 609: a few per style, in an energetic and a mellow
version, each with a written caption and lyrics. Generate each entry as `clips/<name>.mp3`
(30 seconds, using its `caption`, `lyrics`, `bpm` and `language`; `[Instrumental]` means no
vocals). Songs that have no file of their own fall back to these by genre, so this set alone
already gives every style real music, and the 609 can follow later.

## Checking the result

```bash
ls clips/*.mp3 | wc -l                      # 609 when complete (640 with the 31 style clips)
for f in clips/*.mp3; do                    # anything printed here is too long or unreadable
  d=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f") || echo "unreadable $f"
  awk -v d="$d" -v f="$f" 'BEGIN { if (d > 30.5) print "too long " d " " f }'
done
```

## Using the songs (for whoever runs the app, not for the generator)

The seeder looks in `archive/db/library_sample/clips/` (ignored by git), or in the folder named
by `SAMPLE_CLIPS_DIR`. With the clips in place:

```bash
bin/rails library:sample_seed                   # a new database: uses the clips as it seeds
REFRESH_AUDIO=1 bin/rails library:sample_seed   # a database seeded earlier: replaces its audio
```

A song uses `clips/<its id>.mp3` if that exists, otherwise a style clip for its genre, otherwise
the built-in composer. So a partly finished run is usable at any point.

`song_prompts.jsonl` is written from the fixture by `bin/rails library:sample_prompts`; run that
again after a new `library:sample_export`.
