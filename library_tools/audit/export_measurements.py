#!/usr/bin/env python3
"""Turn the library audit's results into a file the app loads into song_measurements, so the Drop Box
compares every new file with the whole library from the first day (rake "library:load_audit[FILE]").

One line per measured file, in Postgres COPY text format, keyed by song id. Verdicts come from
judge.evaluate, exactly as score.py reports them; fingerprints are copied as measured.

  export_measurements.py --songs songs.csv --out measurements.copy results.sqlite [more.sqlite ...]
"""
import argparse, csv, json, os, sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "archive", "lib", "audio_audit"))
from judge import evaluate  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from score import load  # noqa: E402

COLUMNS = ["song_id", "blob_checksum", "measure_version", "score_version", "verdict", "quality", "codec", "kbps",
           "lossless", "bits", "sample_rate", "eff_khz", "duration", "loudness_lufs", "problems", "notes", "data",
           "fingerprint", "fingerprint_keys", "measured_at"]


def copy_value(v):
    """one field in COPY text format"""
    if v is None:
        return r"\N"
    if isinstance(v, bool):
        return "t" if v else "f"
    s = v if isinstance(v, str) else str(v)
    return s.replace("\\", "\\\\").replace("\t", "\\t").replace("\n", "\\n").replace("\r", "\\r")


def signed(v):
    return v - (1 << 32) if v >= (1 << 31) else v


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--songs", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("results", nargs="+")
    a = ap.parse_args()
    songs = {r["key"]: r for r in csv.DictReader(open(a.songs, newline="", encoding="utf-8"))}
    rows = load(a.results)
    written = skipped = 0
    with open(a.out, "w", encoding="utf-8") as out:
        for key, row in rows.items():
            so = songs.get(key)
            if not so or row["status"] != "ok" or not row["data"]:
                skipped += 1
                continue
            m = json.loads(row["data"])
            ev = evaluate(row, m)
            fp = np.frombuffer(row["fp"], dtype=np.uint32) if row["fp"] else None
            lossless = bool(ev.get("lossless"))
            bits, rate = ev.get("res") or (0, 0)
            keys = list(dict.fromkeys(int(v) for v in fp[16:420:4])) if fp is not None else None
            values = {
                "song_id": so["song_id"], "blob_checksum": so["checksum"], "measure_version": row["version"],
                "score_version": 1, "verdict": ev["verdict"], "quality": ev.get("quality"), "codec": ev.get("codec"),
                "kbps": ev.get("kbps"), "lossless": lossless, "bits": bits if lossless else None,
                "sample_rate": rate if lossless else None, "eff_khz": ev.get("eff_khz"),
                "duration": m.get("signal", {}).get("decoded_dur") or (m.get("probe") or {}).get("audio_dur"),
                "loudness_lufs": (m.get("loudness") or {}).get("I"),
                "problems": json.dumps([{"level": lv, "text": t} for lv, t in ev.get("problems", [])], ensure_ascii=False),
                "notes": json.dumps(ev.get("notes", []), ensure_ascii=False),
                "data": json.dumps(m, ensure_ascii=False, separators=(",", ":")),
                "fingerprint": ("\\x" + fp.astype("<u4").tobytes().hex()) if fp is not None else None,
                "fingerprint_keys": ("{" + ",".join(str(signed(k)) for k in keys) + "}") if keys else None,
                "measured_at": row.get("scanned_at") or None,
            }
            out.write("\t".join(copy_value(values[c]) for c in COLUMNS) + "\n")
            written += 1
    print(f"{written} measurements written to {a.out}, {skipped} skipped (not in the song list or not readable)")


if __name__ == "__main__":
    main()
