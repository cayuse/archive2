#!/usr/bin/env python3
"""Judge a folder of new music (Lidarr's root folder, a download) against the library, before anything
is imported. The first half of the importer: it decides, it does not import.

Every incoming file is measured with scan.py's measure_file and judged with score.py's evaluate, so its
numbers compare directly with the library audit's. Each one is matched to the library's copies of the
same recording (same artist, then the fingerprint decides; the same title alone is not enough) and
ranked against them with score.py's strength_of, the rules the dedup uses. The decision:

  new        the library has no copy of this recording: import it
  better     it beats every library copy: import it, and the library copies become superseded
  not better a library copy is as good or better: skip it (the file stays where it is)
  check      something needs a person: the library copy is not measured yet, or the incoming file is broken

  incoming.py --songs songs.csv --library results.sqlite [--library sample.sqlite] --db incoming.sqlite \
              --out report-incoming/ DIR
"""
import argparse, csv, json, os, signal, sqlite3, subprocess, sys, time
from collections import defaultdict
from multiprocessing import Pool

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "archive", "lib", "audio_audit"))
from measure import measure_file, MEASURE_VERSION                                               # noqa: E402
from scan import SCHEMA                                                                         # noqa: E402
from score import load                                                                          # noqa: E402
from judge import RULES, evaluate, ber, album_counts, album_pref, strength_of, why_worse        # noqa: E402
from textnorm import norm_name, COMPILATION, pad                                                    # noqa: E402

AUDIO = (".flac", ".mp3", ".m4a", ".mp4", ".ogg", ".opus", ".wav", ".aac")


def tags_of(path):
    r = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format_tags", "-of", "json", path],
                       capture_output=True, timeout=60)
    t = json.loads(r.stdout or b"{}").get("format", {}).get("tags") or {}
    t = {k.lower(): v for k, v in t.items()}
    def first(*names):
        for n in names:
            if t.get(n):
                return str(t[n])
        return ""
    return {"artist": first("album_artist", "albumartist", "artist"), "track_artist": first("artist"),
            "title": first("title"), "album": first("album"), "track": first("track").split("/")[0],
            "disc": first("disc").split("/")[0], "date": first("date"),
            "mb_recording": first("musicbrainz_trackid", "musicbrainz track id"),
            "mb_album": first("musicbrainz_albumid", "musicbrainz album id")}


def work(job):
    root, rel = job
    path = os.path.join(root, rel)
    t0 = time.time()
    out = {"key": rel, "song_id": None, "status": "ok", "error": None, "md5_ok": None, "data": None, "fp": None}
    try:
        m, fp = measure_file(path, os.path.splitext(rel)[1][1:].lower())
        m["size"] = os.path.getsize(path)
        m["tags"] = tags_of(path)
        out["data"] = json.dumps(m, separators=(",", ":"))
        out["fp"] = fp
    except subprocess.TimeoutExpired as ex:
        out.update(status="timeout", error=str(ex)[:300])
    except Exception as ex:
        out.update(status="fail", error=f"{type(ex).__name__}: {ex}"[:500])
    out["seconds"] = round(time.time() - t0, 2)
    return out


def measure_all(root, db_path, workers):
    db = sqlite3.connect(db_path)
    db.executescript(SCHEMA)
    done = {k for k, v in db.execute("select key, version from measurements") if v == MEASURE_VERSION}
    files = sorted(os.path.relpath(os.path.join(d, f), root) for d, _, fs in os.walk(root) for f in fs
                   if f.lower().endswith(AUDIO) and not f.startswith("."))
    todo = [(root, f) for f in files if f not in done]
    print(f"{len(files)} audio files, {len(todo)} to measure", file=sys.stderr)
    if todo:
        def init():
            signal.signal(signal.SIGINT, signal.SIG_IGN)
            os.nice(5)
        with Pool(workers, initializer=init) as pool:
            for i, r in enumerate(pool.imap_unordered(work, todo), 1):
                db.execute("insert or replace into measurements values (?,?,?,?,?,?,?,?,?,?)",
                           (r["key"], None, MEASURE_VERSION, r["status"], r["error"], None, r["seconds"],
                            time.strftime("%Y-%m-%dT%H:%M:%S"), r["data"], r["fp"]))
                db.commit()
                print(f"  {i}/{len(todo)} {r['key']}", file=sys.stderr)
    return set(files)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--songs", required=True)
    ap.add_argument("--library", action="append", required=True, help="library audit results (any number)")
    ap.add_argument("--db", required=True, help="measurements of the incoming files (resumable)")
    ap.add_argument("--out", required=True)
    ap.add_argument("--workers", type=int, default=2)
    ap.add_argument("dir")
    a = ap.parse_args()

    present = measure_all(a.dir, a.db, a.workers)
    songs = list(csv.DictReader(open(a.songs, newline="", encoding="utf-8")))
    album_songs, album_artist_songs = album_counts(songs)

    # the library's measured copies (read only: the full scan may still be writing)
    lib = {}
    for p in a.library:
        db = sqlite3.connect(f"file:{p}?mode=ro", uri=True)
        for key, ver, status, error, md5_ok, data, fp in db.execute(
                "select key, version, status, error, md5_ok, data, fp from measurements"):
            lib[key] = {"key": key, "status": status, "error": error, "md5_ok": md5_ok, "data": data, "fp": fp}

    inc = [r for r in load([a.db]).values() if r["key"] in present]
    song_by_key = {so["key"]: so for so in songs}
    by_title = defaultdict(list)
    for so in songs:
        by_title[norm_name(so["title"])].append(so)

    def judged(row):
        m = json.loads(row["data"]) if row["data"] else {}
        fp = np.frombuffer(row["fp"], dtype=np.uint32) if row["fp"] else None
        dur = m.get("signal", {}).get("decoded_dur") or 0
        return m, evaluate({**row, "md5_ok": row.get("md5_ok")}, m), fp, dur

    # fingerprint index over the whole library, so a match never depends on the tags (the library
    # credits "Miles On It" to Marshmello, Lidarr to Kane Brown). Sorted (value, file) arrays keep
    # 75,000 files' worth in tens of MB.
    lib_keys = [k for k, r in lib.items() if r["fp"] and k in song_by_key]
    lib_fps = [np.frombuffer(lib[k]["fp"], dtype=np.uint32) for k in lib_keys]
    vals, owners = [], []
    for i, fp in enumerate(lib_fps):
        if len(fp) >= 40:
            v = np.unique(fp[16:420:4]); vals.append(v); owners.append(np.full(len(v), i, dtype=np.int32))
    vals = np.concatenate(vals) if vals else np.zeros(0, np.uint32)
    owners = np.concatenate(owners) if owners else np.zeros(0, np.int32)
    order = np.argsort(vals, kind="stable"); vals, owners = vals[order], owners[order]
    uniq, counts = np.unique(vals, return_counts=True)
    common = set(uniq[counts > 80].tolist())          # values every quiet intro shares
    print(f"library index: {len(lib_keys)} fingerprinted files", file=sys.stderr)

    def fp_candidates(fp):
        hits = defaultdict(int)
        for v in np.unique(fp[:460]):
            if int(v) in common:
                continue
            lo, hi = np.searchsorted(vals, v, "left"), np.searchsorted(vals, v, "right")
            for j in owners[lo:hi]:
                hits[int(j)] += 1
        return [lib_keys[j] for j, c in hits.items() if c >= 3]

    lib_cache = {}
    def library_copy(key):
        if key not in lib_cache:
            row = lib.get(key)
            lib_cache[key] = judged(row) if row else None
        return lib_cache[key]

    results = []
    for row in sorted(inc, key=lambda r: r["key"]):
        m, ev, fp, dur = judged(row)
        t = m.get("tags", {})
        na, nt, nal = norm_name(t.get("artist")), norm_name(t.get("title")), norm_name(t.get("album"))
        def related(so):
            # the same title by this artist (incl. "feat." credits), or on an album of the same name
            k = norm_name(so["artist"])
            return (na and (na in k or (len(k) > 4 and k in na))) or (nal and norm_name(so["album"]) == nal)
        short = norm_name(t.get("title", "").split(" (")[0])
        named = [so for so in (by_title.get(nt, []) if nt else []) + (by_title.get(short, []) if short and short != nt else [])
                 if related(so)]
        cand_keys = set(fp_candidates(fp) if fp is not None else []) | {so["key"] for so in named}
        same, other_versions, unmeasured = [], [], []
        for k in sorted(cand_keys):
            so = song_by_key[k]
            lc = library_copy(k)
            if lc is None or lc[2] is None or fp is None:
                unmeasured.append(so)
                continue
            _, lev, lfp, ldur = lc
            overlap = min(RULES["fp_min_overlap"], int(0.8 * min(len(fp), len(lfp))))
            if overlap < 40:
                continue
            e = ber(fp, lfp, RULES["fp_max_shift"], overlap)
            if e <= RULES["fp_max_ber"]:
                ldur = ldur or float(so["duration"] or 0)
                if abs(dur - ldur) <= max(RULES["dup_dur_s"], RULES["dup_dur_frac"] * max(dur, ldur)):
                    same.append((so, lev, e))
                else:
                    other_versions.append((so, lev, e, "different length"))
            elif so in named:
                other_versions.append((so, lev, e, "different recording"))
        unmeasured = [so for so in unmeasured if so in named]

        pref_in = 1.0 - (0.6 if COMPILATION.search(t.get("album") or "") else 0)
        s_in = strength_of(ev, pref_in)
        if ev["verdict"] == "bad":
            decision, why = "check", "the incoming file is broken: " + "; ".join(p for _, p in ev["problems"])
        elif same:
            ranked = sorted(same, key=lambda x: strength_of(x[1], album_pref(x[0], album_songs, album_artist_songs),
                                                             int(x[0].get("plays") or 0)), reverse=True)
            best_so, best_ev, _ = ranked[0]
            s_best = strength_of(best_ev, album_pref(best_so, album_songs, album_artist_songs))
            if s_in[:5] > s_best[:5]:
                decision = "better"
                why = "; ".join(why_worse(ev, best_ev)) or "better"
            else:
                decision = "not better"
                why = "; ".join(why_worse(best_ev, ev)) or "same quality"
        else:
            decision = "new"
            why = "no copy of this recording in the library" + (
                f" (other versions: {', '.join(sorted(set(r for *_, r in other_versions)))})" if other_versions else "")
        if unmeasured and decision in ("better", "new"):
            decision = "check"
            why = (f"{len(unmeasured)} library copy of this title not measured yet "
                   f"({', '.join(so['file_format'] + ' on ' + repr(so['album']) for so in unmeasured)})")

        def desc(so, lev):
            return f"{lev['codec']} {lev['kbps']}k {lev['verdict']}, \"{so['album']}\""
        results.append({
            "decision": decision, "why": why, "file": row["key"], "artist": t.get("artist"),
            "album": t.get("album"), "track": t.get("track"), "title": t.get("title"),
            "codec": ev["codec"], "kbps": ev["kbps"], "eff_khz": ev["eff_khz"], "verdict": ev["verdict"],
            "quality": ev["quality"],
            "problems": " | ".join(p for _, p in ev["problems"]), "notes": " | ".join(ev["notes"]),
            "lufs": (m.get("loudness") or {}).get("I"),
            "library_copies": " || ".join(desc(so, lev) for so, lev, _ in same),
            "supersedes": " ".join(so["song_id"] for so, _, _ in same) if decision == "better" else "",
            "other_versions": " || ".join(f"{desc(so, lev)} ({r})" for so, lev, _, r in other_versions),
        })

    os.makedirs(a.out, exist_ok=True)
    cols = list(results[0].keys()) if results else ["decision"]
    with open(os.path.join(a.out, "incoming.csv"), "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=cols); w.writeheader(); w.writerows(results)
    albums = defaultdict(list)
    for r in results:
        albums[(r["artist"], r["album"], os.path.dirname(r["file"]))].append(r)
    with open(os.path.join(a.out, "summary.txt"), "w", encoding="utf-8") as fh:
        def p(*x): print(*x, file=fh); print(*x)
        tot = defaultdict(int)
        for r in results: tot[r["decision"]] += 1
        p(f"{len(results)} incoming files: " + "   ".join(f"{k} {tot[k]}" for k in ("new", "better", "not better", "check")))
        for (artist, album, d), rs in sorted(albums.items()):
            c = defaultdict(int)
            for r in rs: c[r["decision"]] += 1
            f0 = rs[0]
            p(f"\n{artist} — {album}  ({f0['codec']} {f0['kbps']}k, {len(rs)} tracks)   "
              + "   ".join(f"{k} {c[k]}" for k in ("new", "better", "not better", "check") if c[k]))
            for r in sorted(rs, key=lambda r: int(r["track"] or 0)):
                p(f"   {r['track']:>2} {pad(r['title'], 38)} {r['decision']:10}  {r['why'][:70]}")
                if r["library_copies"]:
                    p(f"      library: {r['library_copies'][:110]}")


if __name__ == "__main__":
    main()
