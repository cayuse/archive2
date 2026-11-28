#!/usr/bin/env python3
"""Library audit, step 1: measure every audio file. Deterministic signal checks only, no AI.

For each stored file this records raw measurements (not verdicts) in a SQLite results file, so the
scoring rules in score.py can be changed and re-run without decoding anything again:

  integrity  checksum against the database, strict ffmpeg decode errors, mp3val (MP3),
             flac -t (FLAC's own MD5 of the audio), decoded length against the container and the
             database
  damage     bursts far past full scale (corrupt frames), digital silences inside the music,
             abrupt level jumps, clicks, a loud last instant (cut-off file)
  quality    loudness (EBU R128), true peak, clipping, DC offset, stereo correlation, and the
             spectrum in 250 Hz bands: an encoder's lowpass shows where the file really stops
  identity   a Chromaprint fingerprint of the first 120 s (what AcoustID uses), for dedup

Resumable: files already measured with the current MEASURE_VERSION are skipped. Spreadable: --shard
i/n splits the library by key so several machines (or runs) can each take a part; score.py reads
any number of result files. Files are read either from a local directory (on bigballs) or over SSH,
one copy at a time into a scratch directory that is emptied as it goes.

  scan.py --songs songs.csv --db results.sqlite --source ssh:sauce@192.168.17.109:/datatank/archive/psql_storage \
          --workers 15 [--sample 500 --seed 1] [--shard 0/2] [--keys k1,k2] [--limit N] [--rescan]
"""
import argparse, base64, csv, hashlib, json, os, re, signal, sqlite3, subprocess, sys, time, zlib
from multiprocessing import Pool, current_process


# the measuring and judging code is shared with the app's Drop Box: archive/lib/audio_audit
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "archive", "lib", "audio_audit"))
from measure import MEASURE_VERSION, TIMEOUT, md5_b64, measure_file  # noqa: E402

SCRATCH = os.environ.get("AUDIT_SCRATCH", "/work")


# ---------------------------------------------------------------- fetching

class Source:
    def __init__(self, spec):
        self.spec = spec
        if spec.startswith("ssh:"):
            rest = spec[4:]
            self.host, self.root = rest.split(":", 1)
            self.kind = "ssh"
        else:
            self.kind, self.root = "local", spec.removeprefix("local:")
        self.sock = None

    def path(self, key):
        return f"{self.root}/{key[0:2]}/{key[2:4]}/{key}"

    def open(self):
        # one multiplexed SSH connection per worker process, reused for every file it reads
        if self.kind != "ssh":
            return
        self.sock = f"/tmp/audit-ssh-{os.getpid()}"
        subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ServerAliveInterval=30", "-fNM", "-S", self.sock,
                        self.host], check=True, timeout=60)

    def fetch(self, key, dest):
        if self.kind == "local":
            return self.path(key)
        with open(dest, "wb") as out:
            r = subprocess.run(["ssh", "-S", self.sock, "-o", "BatchMode=yes", self.host, "cat", "--",
                                self.path(key)], stdout=out, stderr=subprocess.PIPE, timeout=TIMEOUT)
        if r.returncode != 0:
            raise FetchError(r.stderr.decode(errors="replace").strip()[:300])
        return dest


class FetchError(Exception):
    pass


# ---------------------------------------------------------------- workers

SRC = None

def init_worker(spec):
    global SRC
    signal.signal(signal.SIGINT, signal.SIG_IGN)
    os.nice(5)
    SRC = Source(spec)
    SRC.open()


def work(row):
    key = row["key"]
    t0 = time.time()
    dest = os.path.join(SCRATCH, f"{current_process().pid}-{key}")
    out = {"key": key, "song_id": row["song_id"], "status": "ok", "error": None, "md5_ok": None,
           "data": None, "fp": None}
    try:
        try:
            path = SRC.fetch(key, dest)
        except (FetchError, subprocess.TimeoutExpired) as ex:
            out.update(status="fetch_error", error=str(ex)); return out
        if not os.path.exists(path):
            out.update(status="missing", error="file not found"); return out
        size = os.path.getsize(path)
        out["md5_ok"] = int(md5_b64(path) == row["checksum"])
        m, fp = measure_file(path, row["file_format"])
        m["size"] = size
        m["db"] = {"duration": int(row["duration"] or 0), "byte_size": int(row["byte_size"] or 0),
                   "format": row["file_format"]}
        out["data"] = json.dumps(m, separators=(",", ":"))
        out["fp"] = fp
    except subprocess.TimeoutExpired as ex:
        out.update(status="timeout", error=str(ex)[:300])
    except Exception as ex:
        out.update(status="fail", error=f"{type(ex).__name__}: {ex}"[:500])
    finally:
        if SRC.kind == "ssh" and os.path.exists(dest):
            os.remove(dest)
        out["seconds"] = round(time.time() - t0, 2)
    return out


# ---------------------------------------------------------------- driver

SCHEMA = """
create table if not exists measurements (
  key text primary key, song_id text, version integer, status text, error text, md5_ok integer,
  seconds real, scanned_at text, data text, fp blob);
"""

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--songs", required=True)
    ap.add_argument("--db", required=True)
    ap.add_argument("--source", required=True)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--sample", type=int)
    ap.add_argument("--seed", default="1")
    ap.add_argument("--shard")
    ap.add_argument("--keys")
    ap.add_argument("--limit", type=int)
    ap.add_argument("--rescan", action="store_true", help="measure again even if current")
    ap.add_argument("--retry-failed", action="store_true")
    a = ap.parse_args()

    rows = list(csv.DictReader(open(a.songs, newline="")))
    if a.keys:
        want = set(a.keys.split(","))
        rows = [r for r in rows if r["key"] in want]
    if a.shard:
        i, n = map(int, a.shard.split("/"))
        rows = [r for r in rows if zlib.crc32(r["key"].encode()) % n == i]
    # a stable pseudo-random order: a sample is the same files every run, and a full run
    # touches every corner of the library early instead of going key by key
    rows.sort(key=lambda r: hashlib.sha1((a.seed + r["key"]).encode()).digest())
    if a.sample:
        rows = rows[: a.sample]

    db = sqlite3.connect(a.db, timeout=60)
    db.execute("pragma journal_mode=wal")
    db.executescript(SCHEMA)
    if not a.rescan:
        done = {k for k, v, s in db.execute("select key, version, status from measurements")
                if v == MEASURE_VERSION and (s == "ok" or not a.retry_failed)}
        rows = [r for r in rows if r["key"] not in done]
    if a.limit:
        rows = rows[: a.limit]
    total = len(rows)
    print(f"{total} files to measure with {a.workers} workers", flush=True)
    if not total:
        return

    t0 = time.time(); n = 0; audio_s = 0.0; bad = 0
    stop = False
    def on_int(*_):
        nonlocal stop
        if not stop:
            print("\nstopping: results so far are saved; run again to resume", flush=True)
        stop = True
    signal.signal(signal.SIGINT, on_int)
    signal.signal(signal.SIGTERM, on_int)

    pool = Pool(a.workers, initializer=init_worker, initargs=(a.source,))
    try:
        for out in pool.imap_unordered(work, rows, chunksize=1):
            db.execute("insert or replace into measurements values (?,?,?,?,?,?,?,datetime('now'),?,?)",
                       (out["key"], out["song_id"], MEASURE_VERSION, out["status"], out["error"], out["md5_ok"],
                        out["seconds"], out["data"], out["fp"]))
            n += 1
            if out["status"] != "ok":
                bad += 1
            else:
                audio_s += json.loads(out["data"]).get("signal", {}).get("decoded_dur", 0)
            if n % 25 == 0 or n == total:
                db.commit()
                el = time.time() - t0
                print(f"{n}/{total}  {n / el:.2f} files/s  {audio_s / el:.0f}x realtime  "
                      f"not ok: {bad}  eta {(total - n) / (n / el) / 3600:.1f} h", flush=True)
            if stop and n < total:
                break
    finally:
        db.commit()
        pool.terminate()
        pool.join()


if __name__ == "__main__":
    main()
