# The analysis API

How a machine with a GPU fills in what stations need for songs the Drop Box has added. The
server never analyses audio; an outside program reads what is waiting, downloads the files,
analyses them, and writes the results back.

**The API describes itself.** `GET /api/v1/analysis` (with a key) returns every endpoint, the
rules each write is checked against, and the definitions of the data (how the dials and
sound-alike lists are computed, including the phrases behind each dial). That response is the
contract (`AnalysisApiGuide`); this page only covers what the client is not told.

## Keys

A `ServiceKey` of scope `analysis`. Not a person's login, and a person's login is not a key.

```bash
kamal app exec --reuse 'bin/rails "analysis:key[my-pc]"'     # prints the key, once
kamal app exec --reuse 'bin/rails analysis:keys'              # name, last use, write count
kamal app exec --reuse 'bin/rails "analysis:revoke[my-pc]"'
```

Only the key's SHA-256 digest is stored. Each use records the time and address; each write is
logged (`[analysis] key=<name> ...`) and counted on the key.

## What a key can and cannot do

| Can | Cannot |
|---|---|
| List songs with their artist, album, genre and length | See users, playlists, stations, settings or anything else |
| Download any song's audio file | Add, change or delete songs, files, artists, albums or genres |
| Read stored features, embeddings, sound-alike lists, genre adjacency | Call any other endpoint of the app |
| Write `song_audio_features`, `song_embeddings`, `song_neighbors`, `genre_affinities` | Write any other table |

Writes go through `AnalysisWriter` only. A request is checked in full, then written in one
transaction: one bad item and nothing is written. The checks: the model must be the library's
own; dials 0..1; signal values in plausible ranges; vectors of exactly the library's size, finite,
not all zero; songs and neighbours must exist (neighbours must be analysed); no self or repeated
neighbours, best first; an already-analysed song is refused without `replace`; replacing the genre
adjacency table with something under half its size is refused without `allow_shrink`. Request
sizes are capped.

What that does not protect against: plausible-looking wrong numbers. A client that computes
dials or neighbours badly can still make stations play badly. The remedy is a database backup
before a large run (`archive/KAMAL_DEPLOY.md`), and revoking the key.

## Code

`Api::V1::AnalysisController` (inherits `ActionController::API`: no session, no user),
`AnalysisWriter`, `AnalysisApiGuide`, `ServiceKey`, `lib/tasks/analysis.rake`,
`Song.awaiting_analysis` (the reserve).
