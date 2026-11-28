#!/usr/bin/env python3
"""Measure and judge one audio file for the app (AudioAudit). Prints one JSON object:

  measure_version, score_version
  evaluation    verdict (ok / weak / flawed / bad), quality 0-100, codec, kbps, lossless, res
                [bits, sample rate] for real lossless, eff_khz (where the music really stops),
                problems [[level, text]], notes [text]
  measurements  the raw numbers (measure.py), for re-judging later without decoding again
  fingerprint   Chromaprint, raw: base64 of little-endian uint32s (first 120 s), for matching copies
  acoustid      Chromaprint, compressed, and the duration fpcalc saw: what AcoustID's lookup takes

  cli.py FILE [FORMAT]

Exit status 0 with the JSON, or 1 with {"error": ...} when the file could not be measured at all.
"""
import base64, json, os, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))   # python -I leaves the script dir off the path
from measure import MEASURE_VERSION, measure_file      # noqa: E402
from judge import SCORE_VERSION, evaluate              # noqa: E402


def acoustid_print(path):
    r = subprocess.run(["fpcalc", "-json", "-length", "120", path], capture_output=True, timeout=300)
    try:
        j = json.loads(r.stdout)
        return {"fingerprint": j["fingerprint"], "duration": j["duration"]}
    except Exception:
        return None


def main():
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    path = sys.argv[1]
    fmt = sys.argv[2] if len(sys.argv) > 2 else os.path.splitext(path)[1].lstrip(".").lower()
    try:
        m, fp = measure_file(path, fmt)
        ev = evaluate({"status": "ok", "error": None, "md5_ok": None}, m)
    except Exception as ex:
        print(json.dumps({"error": f"{type(ex).__name__}: {ex}"[:500]}))
        return 1
    ev["res"] = list(ev.get("res") or (0, 0))
    out = {
        "measure_version": MEASURE_VERSION, "score_version": SCORE_VERSION,
        "evaluation": ev, "measurements": m,
        "fingerprint": base64.b64encode(fp).decode() if fp else None,
        "acoustid": acoustid_print(path) if fp else None,
    }
    sys.stdout.write(json.dumps(out, separators=(",", ":"), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
