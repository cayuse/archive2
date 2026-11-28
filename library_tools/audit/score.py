#!/usr/bin/env python3
"""Library audit, step 2: turn measurements into verdicts, scores and duplicate groups.

Reads the result files written by scan.py (any number: shards from several machines) and the song
list, and writes reports. Never touches audio and never touches the database, so the rules below can
be tuned and re-run in seconds.

  score.py --songs songs.csv --out report/ results.sqlite [more.sqlite ...]

Every file gets:
  verdict   bad      broken in a way you hear, or unreadable: replace it
            flawed   plays, but has a fault: a few damaged frames, channels out of phase, a "lossless"
                     file made from a lossy one, cut off at the end: replace it when a better copy turns up
            weak     intact, but low fidelity: low bitrate, or the music stops well below what its bitrate
                     should carry (made from a lower-quality copy, or an old encoder)
            ok
  problems  the reasons, in words
  quality   0-100, for ranking copies of the same recording. Intact real lossless is 100; lossy
            copies score by how far up the spectrum they really go and their bitrate; flaws cost points.

Duplicates are found by sound, not by tags: two files are the same recording when their Chromaprint
fingerprints line up (bit error rate under RULES["fp_max_ber"]) and their lengths agree. Within a group
the best copy is kept by fixed rules: intact beats flawed beats bad, then real lossless, then real
frequency content, then bitrate. Nothing is deleted here; the reports are for review.
"""
import argparse, csv, json, os, re, sqlite3, sys
from collections import defaultdict, Counter

import numpy as np

# the measuring and judging code is shared with the app's Drop Box: archive/lib/audio_audit
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "archive", "lib", "audio_audit"))
from judge import (SCORE_VERSION, RULES, RANK, evaluate, find_duplicates, kbps_tier, album_counts,  # noqa: E402
                   album_pref, strength_of, why_worse, norm_name, COMPILATION, ber)

# ---------------------------------------------------------------- main

def load(paths):
    rows = {}
    for path in paths:
        db = sqlite3.connect(path)
        for key, song_id, ver, status, error, md5_ok, data, fp in db.execute(
                "select key, song_id, version, status, error, md5_ok, data, fp from measurements"):
            old = rows.get(key)
            if old and (old["version"], old["status"] == "ok") >= (ver, status == "ok"):
                continue
            rows[key] = {"key": key, "song_id": song_id, "version": ver, "status": status, "error": error,
                         "md5_ok": md5_ok, "data": data, "fp": fp}
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--songs", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("results", nargs="+")
    a = ap.parse_args()
    songs = {r["key"]: r for r in csv.DictReader(open(a.songs, newline="", encoding="utf-8"))}
    rows = load(a.results)
    os.makedirs(a.out, exist_ok=True)

    files = []
    for key, row in rows.items():
        m = json.loads(row["data"]) if row["data"] else {}
        ev = evaluate(row, m)
        so = songs.get(key, {})
        fp = np.frombuffer(row["fp"], dtype=np.uint32) if row["fp"] else None
        files.append({"key": key, "song": so, "ev": ev, "fp": fp,
                      "dur": (m.get("signal", {}).get("decoded_dur") or float(so.get("duration") or 0))})

    by_name = defaultdict(list)
    for i, f in enumerate(files):
        by_name[(norm_name(f["song"].get("artist")), norm_name(f["song"].get("title")))].append(i)
    extra = [(L[x], L[y]) for (na, nt), L in by_name.items() if na and nt and 1 < len(L) <= 40
             for x in range(len(L)) for y in range(x + 1, len(L))]
    groups, same, related = find_duplicates([f["key"] for f in files], [f["fp"] for f in files],
                                            [f["dur"] for f in files], extra)
    # on a tie, prefer the copy on the artist's own album over a hits package or a compilation
    album_songs, album_artist_songs = album_counts(songs.values())
    def strength(f):
        return strength_of(f["ev"], album_pref(f["song"], album_songs, album_artist_songs),
                           int(f["song"].get("plays") or 0), f["key"])
    for f in files:
        f["group"] = ""; f["action"] = "keep"; f["why"] = ""
    for gi, g in enumerate(sorted(groups, key=len, reverse=True), 1):
        members = sorted((files[i] for i in g), key=strength, reverse=True)
        best = members[0]
        for f in members:
            f["group"] = f"D{gi:05d}"
        best["action"] = "keep (best copy)"
        for f in members[1:]:
            f["action"] = "drop (duplicate)"
            b = best["ev"]; e = f["ev"]
            reasons = []
            if RANK[b["verdict"]] > RANK[e["verdict"]]: reasons.append(f"this copy is {e['verdict']}")
            if b["lossless"] and not e["lossless"]: reasons.append("kept copy is lossless")
            elif b["lossless"] and tuple(b.get("res") or ()) > tuple(e.get("res") or ()):
                reasons.append("kept copy is {}-bit/{:g} kHz".format(b["res"][0], b["res"][1] / 1000))
            if min(19.5, b["eff_khz"] or 0) > min(19.5, e["eff_khz"] or 0) + 0.4: reasons.append(f"kept copy goes to {b['eff_khz']:g} kHz, this one {e['eff_khz']:g}")
            if not reasons and kbps_tier(b["kbps"] or 0) > kbps_tier(e["kbps"] or 0):
                reasons.append(f"kept copy is {b['kbps']} kbps, this one {e['kbps']}")
            if not reasons and album_pref(best["song"], album_songs, album_artist_songs) > album_pref(f["song"], album_songs, album_artist_songs):
                reasons.append(f"same quality; kept the copy on \"{best['song'].get('album')}\"")
            if not reasons: reasons.append("same quality")
            f["why"] = "; ".join(reasons)

    # songs whose best (or only) copy is broken / poor
    for f in files:
        f["replace"] = ""
        if f["action"].startswith("drop"):
            continue
        if f["ev"]["verdict"] == "bad":
            f["replace"] = "replace (broken)"
        elif f["ev"]["verdict"] == "flawed":
            f["replace"] = "upgrade when possible"
        elif f["ev"]["verdict"] == "weak":
            f["replace"] = "low fidelity"

    cols = ["verdict", "quality", "replace", "action", "group", "why", "artist", "title", "album", "codec", "kbps",
            "eff_khz", "problems", "notes", "plays", "downs", "song_id", "key", "original_filename"]
    def line(f):
        ev, so = f["ev"], f["song"]
        return {"verdict": ev["verdict"], "quality": ev["quality"], "replace": f["replace"], "action": f["action"],
                "group": f["group"], "why": f["why"], "artist": so.get("artist"), "title": so.get("title"),
                "album": so.get("album"), "codec": ev["codec"], "kbps": ev["kbps"], "eff_khz": ev["eff_khz"],
                "problems": " | ".join(t for _, t in ev["problems"]), "notes": " | ".join(ev["notes"]),
                "plays": so.get("plays"), "downs": so.get("downs"), "song_id": so.get("song_id") or "",
                "key": f["key"], "original_filename": so.get("original_filename")}
    def write(name, items, sort):
        with open(os.path.join(a.out, name), "w", newline="", encoding="utf-8") as fh:
            w = csv.DictWriter(fh, fieldnames=cols); w.writeheader()
            for f in sorted(items, key=sort):
                w.writerow(line(f))
    order = {"bad": 0, "flawed": 1, "weak": 2, "ok": 3}
    write("files.csv", files, lambda f: (order[f["ev"]["verdict"]], f["ev"]["quality"], f["song"].get("artist") or ""))
    write("replace.csv", [f for f in files if f["replace"]],
          lambda f: (order[f["ev"]["verdict"]], -int(f["song"].get("plays") or 0), f["song"].get("artist") or ""))
    write("duplicates.csv", [f for f in files if f["group"]], lambda f: (f["group"], f["action"] != "keep (best copy)"))

    n = len(files)
    vc = Counter(f["ev"]["verdict"] for f in files)
    pc = Counter(re.sub(r"[\d:.,]+", "#", t) for f in files for _, t in f["ev"]["problems"])
    nc = Counter(re.sub(r"[\d:.,\-\[\] ]+", " ", t).strip() for f in files for t in f["ev"]["notes"])
    drops = [f for f in files if f["action"].startswith("drop")]
    with open(os.path.join(a.out, "summary.txt"), "w", encoding="utf-8") as fh:
        def p(*x): print(*x, file=fh); print(*x)
        p(f"Library audit (score v{SCORE_VERSION}): {n} files measured")
        p(f"  ok {vc['ok']}   weak {vc['weak']}   flawed {vc['flawed']}   bad {vc['bad']}")
        p(f"  duplicate groups {len(groups)}: {len(drops)} files could go, "
          f"{sum(f['song'].get('byte_size') and int(f['song']['byte_size']) or 0 for f in drops) / 1e9:.1f} GB")
        p(f"  same recording at a different length (edits, not merged): {len(related)} pairs")
        p(f"  to replace (best copy broken): {sum(f['replace'].startswith('replace') for f in files)}"
          f"   to upgrade (best copy flawed): {sum(f['replace'].startswith('upgrade') for f in files)}"
          f"   low fidelity only: {sum(f['replace'] == 'low fidelity' for f in files)}")
        p("\nProblems:")
        for t, c in pc.most_common(): p(f"  {c:6d}  {t}")
        p("\nNotes (do not affect the verdict):")
        for t, c in nc.most_common(12): p(f"  {c:6d}  {t}")


if __name__ == "__main__":
    main()
