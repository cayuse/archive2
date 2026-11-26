#!/usr/bin/env python3
"""Audio analysis of the mirrored archive on this PC's GPU.

For every song: a 512-d CLAP embedding (laion/larger_clap_music_and_speech; mean of up to 6 ten-second windows
spread across the track, L2-normalised) plus simple signal features (loudness, tempo, brightness).
CLAP embeds text into the same space, so similarity AND text steering come from one vector.

  venv\\Scripts\\python scripts\\analyze_audio.py [--limit N] [--workers N]

Input : work/songs.tsv (song_id, blob_key, ...), audio at AUDIO_ROOTS/XX/YY/<key>
Output: work/audio/shard_*.npz (ids, emb float16), work/audio/features.jsonl, work/audio/errors.jsonl
Resumable: songs already in a shard are skipped; files not mirrored yet are skipped and picked up next run.
"""
import argparse, json, os, subprocess, sys, time

os.environ.setdefault("HF_HUB_DISABLE_PROGRESS_BARS", "1")
os.environ.setdefault("TRANSFORMERS_VERBOSITY", "error")
os.environ.setdefault("TQDM_DISABLE", "1")
# one thread per worker process: 14 workers each grabbing every core stalls the machine
for _v in ("OMP_NUM_THREADS", "MKL_NUM_THREADS", "OPENBLAS_NUM_THREADS", "NUMBA_NUM_THREADS", "NUMEXPR_NUM_THREADS"):
    os.environ.setdefault(_v, "1")
from multiprocessing import Pool
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
# Where the audio lives: files already copied locally, then the ZFS clone of the blob store that
# bigballs shares under //bigballs/downloads (read straight over the network, nothing copied).
AUDIO_ROOTS = [ROOT / "audio", Path(os.environ.get("ARCHIVE_AUDIO", "//bigballs/downloads/archive_audio_scratch"))]
OUT = ROOT / "work" / "audio"
MODEL = "laion/larger_clap_music_and_speech"
SR = 48000
WIN = 10 * SR
MAX_WINDOWS = 6
MAX_SECONDS = 1200  # audiobooks and DJ mixes: analyse the first 20 minutes only

_fe = None


def _init():
    global _fe
    from transformers import ClapFeatureExtractor
    _fe = ClapFeatureExtractor.from_pretrained(MODEL)


def decode(path):
    # Second attempt forces the MP3 reader: some files are MP3 audio under a .wav name or header,
    # which ffmpeg's format guess gets wrong.
    err = ""
    for force in ([], ["-f", "mp3"]):
        p = subprocess.run(["ffmpeg", "-v", "error", "-nostdin"] + force + ["-i", str(path), "-vn", "-t", str(MAX_SECONDS),
                            "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"], capture_output=True)
        y = np.frombuffer(p.stdout, dtype=np.float32)
        if y.size >= SR:  # at least one second of audio
            return y
        err = err or p.stderr.decode("utf-8", "replace")[:200].strip() or "under one second of audio"
    raise RuntimeError("decode failed: " + err)


def work(row):
    song_id, key = row
    path = next((p for p in (r / key[0:2] / key[2:4] / key for r in AUDIO_ROOTS) if p.exists()), None)
    if path is None:
        return song_id, "missing", None, None
    return work_path((song_id, path))


def work_path(row):
    """Analyse one audio file at a known path. Used by the bulk run above and by archive_sync.py,
    so songs analysed later are windowed exactly like the original library."""
    song_id, path = row
    try:
        if _fe is None:
            _init()
        import librosa, librosa.feature.rhythm
        y = decode(path)
        dur = y.size / SR
        n = max(1, min(MAX_WINDOWS, int(dur // 10)))
        if y.size <= WIN:
            wins = [np.resize(y, WIN)]  # loop very short tracks up to ten seconds
        else:
            lo, hi = int(0.05 * y.size), int(0.95 * y.size) - WIN
            hi = max(hi, lo)
            starts = np.linspace(lo, hi, n).astype(int) if n > 1 else [max(0, (y.size - WIN) // 2)]
            wins = [y[s:s + WIN] for s in starts]
        feats = _fe(wins, sampling_rate=SR, return_tensors="np")

        # signal features on the middle 60 seconds at 24 kHz
        mid = y.size // 2
        seg = y[max(0, mid - 30 * SR): mid + 30 * SR][::2].astype(np.float32)
        sr2 = SR // 2
        onset = librosa.onset.onset_strength(y=seg, sr=sr2)
        tempo = float(np.atleast_1d(librosa.feature.rhythm.tempo(onset_envelope=onset, sr=sr2))[0])
        cent = float(librosa.feature.spectral_centroid(y=seg, sr=sr2).mean())
        rms = float(np.sqrt(np.mean(np.square(y, dtype=np.float64))))
        peak = float(np.max(np.abs(y)))
        info = {
            "song_id": song_id,
            "analyzed_seconds": round(dur, 2),
            "windows": len(wins),
            "loudness_db": round(20 * np.log10(max(rms, 1e-9)), 2),
            "peak_db": round(20 * np.log10(max(peak, 1e-9)), 2),
            "tempo_bpm": round(tempo, 1),
            "brightness_hz": round(cent, 1),
            "onset_strength": round(float(onset.mean()), 4),
        }
        return song_id, None, info, (feats["input_features"].astype(np.float32), np.asarray(feats["is_longer"]))
    except Exception as e:
        return song_id, "%s: %s" % (type(e).__name__, str(e)[:300]), None, None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--workers", type=int, default=14)
    ap.add_argument("--shard", type=int, default=2000)
    a = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)

    import torch
    from transformers import ClapModel

    rows = [l.rstrip("\n").split("\t")[:2] for l in open(ROOT / "work" / "songs.tsv", encoding="utf-8") if l.strip()]
    done = set()
    for f in sorted(OUT.glob("shard_*.npz")):
        done.update(np.load(f, allow_pickle=False)["ids"].tolist())
    errp = OUT / "errors.jsonl"
    if errp.exists():
        for l in open(errp, encoding="utf-8"):
            done.add(json.loads(l)["song_id"])
    todo = [r for r in rows if r[0] not in done]
    if a.limit:
        todo = todo[:a.limit]
    print("songs %d, done %d, to do %d" % (len(rows), len(done), len(todo)), flush=True)
    if not todo:
        return

    dev = "cuda"
    t = time.time()
    model = ClapModel.from_pretrained(MODEL, torch_dtype=torch.float16).to(dev).eval()
    print("model loaded in %.0fs" % (time.time() - t), flush=True)

    def embed(x, longer):
        with torch.no_grad():
            out = model.get_audio_features(input_features=torch.from_numpy(x).to(dev, torch.float16),
                                           is_longer=torch.from_numpy(longer).to(dev))
        if not torch.is_tensor(out):
            out = out.pooler_output
        return out.float().cpu().numpy()

    ids, embs = [], []
    shard_no = len(list(OUT.glob("shard_*.npz")))

    def flush():
        nonlocal ids, embs, shard_no
        if ids:
            np.savez(OUT / ("shard_%04d.npz" % shard_no), ids=np.array(ids), emb=np.stack(embs).astype(np.float16))
            shard_no += 1
            ids, embs = [], []

    t0, n, missing, errs = time.time(), 0, 0, 0
    pend = []  # (song_id, info, n_windows)
    px, pl = [], []
    featfh = open(OUT / "features.jsonl", "a", encoding="utf-8")
    errfh = open(errp, "a", encoding="utf-8")

    def run_batch():
        nonlocal pend, px, pl
        if not pend:
            return
        e = embed(np.concatenate(px), np.concatenate(pl))
        i = 0
        for song_id, info, k in pend:
            v = e[i:i + k].mean(axis=0)
            i += k
            v /= max(np.linalg.norm(v), 1e-9)
            ids.append(song_id)
            embs.append(v)
            featfh.write(json.dumps(info) + "\n")
            if len(ids) >= a.shard:
                featfh.flush()
                flush()
        pend, px, pl = [], [], []

    with Pool(a.workers, initializer=_init) as pool:
        for song_id, err, info, feats in pool.imap_unordered(work, todo, chunksize=2):
            n += 1
            if err == "missing":
                missing += 1
            elif err:
                errs += 1
                errfh.write(json.dumps({"song_id": song_id, "error": err}) + "\n")
                errfh.flush()
            else:
                pend.append((song_id, info, feats[0].shape[0]))
                px.append(feats[0])
                pl.append(feats[1])
                if sum(k for _, _, k in pend) >= 96:
                    run_batch()
            if n % 500 == 0:
                print("%d/%d  %.1f songs/s  missing %d  errors %d" % (n, len(todo), n / (time.time() - t0), missing, errs), flush=True)
    run_batch()
    featfh.close()
    flush()
    print("DONE %d processed, %d not mirrored yet, %d errors, %.0fs" % (n - missing - errs, missing, errs, time.time() - t0), flush=True)


if __name__ == "__main__":
    main()
