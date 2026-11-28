"""Measure one audio file: deterministic signal checks, no AI. Raw numbers, not verdicts (judge.py
turns them into verdicts), so the rules can change without decoding anything again.

  integrity  strict ffmpeg decode errors, mp3val (MP3), flac -t (FLAC's own MD5 of the audio),
             decoded length against the container
  damage     bursts far past full scale (corrupt frames), digital silences inside the music,
             abrupt level jumps, clicks, a loud last instant (cut-off file)
  quality    loudness (EBU R128), true peak, clipping, DC offset, stereo correlation, and the
             spectrum in 250 Hz bands: an encoder's lowpass shows where the file really stops
  identity   a Chromaprint fingerprint of the first 120 s (what AcoustID uses)

Shared by the library audit (library_tools/audit/scan.py) and the Drop Box (cli.py, called from
AudioAudit in the app). Needs ffmpeg, mp3val, flac, fpcalc (libchromaprint-tools), numpy, scipy.
"""
import base64, hashlib, json, re, subprocess

import numpy as np
from scipy.signal import welch

MEASURE_VERSION = 2
TIMEOUT = 900


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, timeout=TIMEOUT, **kw)


def md5_b64(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return base64.b64encode(h.digest()).decode()


def count_log(lines):
    """Lines of an ffmpeg log made with -loglevel level+info: errors and warnings, counting repeats."""
    errors = warnings = 0
    sample = []
    last = None
    for line in lines:
        m = re.search(r"Last message repeated (\d+) times", line)
        if m:
            if last == "error":
                errors += int(m.group(1))
            elif last == "warning":
                warnings += int(m.group(1))
            continue
        if "[error]" in line or "[fatal]" in line:
            errors += 1; last = "error"
        elif "[warning]" in line:
            warnings += 1; last = "warning"
        else:
            last = None
            continue
        if len(sample) < 6:
            sample.append(re.sub(r" @ 0x[0-9a-f]+", "", line.strip())[:160])
    return errors, warnings, sample


def probe(path):
    p = json.loads(run(["ffprobe", "-v", "error", "-show_format", "-show_streams", "-of", "json", path]).stdout or b"{}")
    audio = [s for s in p.get("streams", []) if s.get("codec_type") == "audio"]
    if not audio:
        return None
    a = audio[0]
    fmt = p.get("format", {})
    tags = {k.lower(): v for k, v in (fmt.get("tags") or {}).items()}
    return {
        "codec": a.get("codec_name"), "profile": a.get("profile"),
        "sample_rate": int(a.get("sample_rate") or 0), "channels": a.get("channels"),
        "bits": int(a.get("bits_per_raw_sample") or a.get("bits_per_sample") or 0),
        "stream_kbps": round(int(a.get("bit_rate") or 0) / 1000),
        "format_kbps": round(int(fmt.get("bit_rate") or 0) / 1000),
        "container": fmt.get("format_name"),
        "container_dur": round(float(fmt.get("duration") or 0), 3),
        "audio_dur": round(float(a.get("duration") or 0), 3),
        "encoder": (tags.get("encoder") or tags.get("encoded_by") or "")[:80],
        "has_cover": any(s.get("codec_type") == "video" for s in p.get("streams", [])),
        "audio_streams": len(audio),
    }


def loudness(lines):
    text = "\n".join(lines)
    i = text.rfind("Summary:")
    if i < 0:
        return {}
    s = text[i:]
    g = lambda k: (lambda m: float(m.group(1)) if m else None)(re.search(k + r":\s+(-?[\d.]+|-inf)", s.replace("-inf", "-200")))
    return {"lufs": g(r"\bI"), "lra": g("LRA"), "true_peak_db": g("Peak")}


def runs_of(mask):
    d = np.diff(np.concatenate([[0], mask.astype(np.int8), [0]]))
    return np.where(d == 1)[0], np.where(d == -1)[0]


def analyse(x, sr):
    m = {}
    n = len(x)
    m["decoded_dur"] = round(n / sr, 3)
    if n < sr:
        m["too_short"] = True
        return m
    ax = np.abs(x)
    peak_t = ax.max(1)
    m["sample_peak"] = round(float(peak_t.max()), 4)
    m["over_full_scale"] = int((peak_t > 1.0).sum())
    hot_runs = 0
    for c in range(x.shape[1]):
        st, en = runs_of(ax[:, c] >= 0.999)
        hot_runs += int(((en - st) >= 3).sum())
    m["clip_runs"] = hot_runs
    m["p999"] = round(float(np.quantile(peak_t[:: max(1, n // 2_000_000)], 0.999)), 4)

    # bursts far past full scale: decoders only go there on corrupt data (or absurd gain)
    big = np.where(peak_t > 1.25)[0]
    events = []
    if len(big):
        cuts = np.where(np.diff(big) > sr // 100)[0]
        starts = np.concatenate([[0], cuts + 1]); ends = np.concatenate([cuts, [len(big) - 1]])
        for s, e in zip(starts, ends):
            i0, i1 = big[s], big[e]
            ctx = np.concatenate([peak_t[max(0, i0 - sr):max(0, i0 - sr // 50)], peak_t[i1 + sr // 50:i1 + sr]])
            events.append({"t": round(i0 / sr, 3), "peak": round(float(peak_t[i0:i1 + 1].max()), 3),
                           "ms": round((i1 - i0 + 1) / sr * 1000, 1),
                           "ctx_p99": round(float(np.quantile(ctx, 0.99)), 3) if len(ctx) else None})
    m["overshoot_events"] = len(events)
    m["overshoots"] = sorted(events, key=lambda e: -e["peak"])[:20]

    m["dc"] = [round(float(v), 5) for v in x.mean(0)]
    if x.shape[1] == 2:
        l, r = x[:, 0], x[:, 1]
        m["lr_identical"] = bool(np.allclose(l, r, atol=1e-5))
        sl, sr_ = float(l.std()), float(r.std())
        m["lr_corr"] = round(float(np.corrcoef(l, r)[0, 1]), 4) if sl > 0 and sr_ > 0 else None
        m["lr_balance_db"] = round(20 * np.log10((sl + 1e-12) / (sr_ + 1e-12)), 2)

    mono = x.mean(1)
    B = sr // 100
    k = n // B
    blocks = mono[:k * B].reshape(k, B)
    db = 20 * np.log10(np.sqrt((blocks ** 2).mean(1)) + 1e-10)
    loud = db > -45
    if not loud.any():
        m["silent"] = True
        return m
    first = int(np.argmax(loud)); last = int(k - np.argmax(loud[::-1]))
    m["lead_silence"] = round(first / 100, 2)
    m["trail_silence"] = round((k - last) / 100, 2)
    m["last_100ms_db"] = round(float(db[-10:].mean()), 1)
    m["first_100ms_db"] = round(float(db[:10].mean()), 1)
    mid = db[first:last]
    # silences inside the music: < -90 dB for 20 ms .. 10 s, with the level on both sides
    st, en = runs_of(mid < -90)
    gaps = []
    for s, e in zip(st, en):
        if 2 <= e - s <= 1000:
            before = float(mid[max(0, s - 30):s].mean()) if s > 0 else -200
            after = float(mid[e:e + 30].mean()) if e < len(mid) else -200
            gaps.append({"t": round((first + s) / 100, 2), "ms": int((e - s) * 10),
                         "before_db": round(before, 1), "after_db": round(after, 1)})
    m["gap_count"] = len(gaps)
    m["gaps"] = sorted(gaps, key=lambda g: -min(g["before_db"], g["after_db"]))[:20]
    jumps = np.where(np.abs(np.diff(mid)) > 35)[0]
    m["level_jumps"] = int(len(jumps))
    m["level_jump_times"] = [round((first + j) / 100, 2) for j in jumps[:20]]

    # clicks: an isolated spike in the second difference, in both channels at once
    clicks = 0; click_times = []
    W = sr // 20
    d2 = np.abs(np.diff(x, 2, axis=0))
    kk = len(d2) // W
    if kk:
        blk = d2[:kk * W].reshape(kk, W, x.shape[1])
        med = np.median(blk, axis=1, keepdims=True) + 1e-7
        hit = ((blk / med) > 80) & (blk > 0.08)
        both = hit.all(axis=2) if x.shape[1] == 2 else hit[:, :, 0]
        bi, si = np.where(both)
        if len(bi):
            ts = np.unique(np.round((bi * W + si) / sr, 1))
            clicks = int(len(ts)); click_times = ts[:30].tolist()
    m["clicks"] = clicks
    m["click_times"] = click_times

    # spectrum of the music (silence excluded), 250 Hz bands relative to the 1-4 kHz median
    seg = mono[first * B:last * B]
    f, p = welch(seg, fs=sr, nperseg=4096, noverlap=0)
    pdb = 10 * np.log10(p + 1e-30)
    ref = float(np.median(pdb[(f >= 1000) & (f <= 4000)]))
    edges = np.arange(0, sr / 2 + 1, 250)
    bands = []
    for lo, hi in zip(edges[:-1], edges[1:]):
        sel = (f >= lo) & (f < hi)
        bands.append(round(float(pdb[sel].mean()) - ref, 1) if sel.any() else None)
    m["bands_250hz"] = bands
    return m


def measure_file(path, fmt):
    m = {"probe": probe(path)}
    if not m["probe"]:
        m["no_audio"] = True
        return m, None
    sr = m["probe"]["sample_rate"] or 44100

    # strict decode, only to count errors: with -err_detect ffmpeg drops the frames it doubts, so
    # its audio is not what a player plays and is not measured
    r = run(["ffmpeg", "-nostats", "-hide_banner", "-loglevel", "level+warning", "-threads", "1",
             "-err_detect", "crccheck+bitstream+buffer", "-i", path, "-map", "0:a:0", "-f", "null", "-"])
    e, w, sample = count_log(r.stderr.decode(errors="replace").splitlines())
    m["ffmpeg_strict"] = {"rc": r.returncode, "errors": e, "warnings": w, "sample": sample}
    # normal decode, as a player hears it: errors, loudness, true peak and the PCM
    r = run(["ffmpeg", "-nostats", "-hide_banner", "-loglevel", "level+info", "-threads", "1",
             "-i", path, "-map", "0:a:0",
             "-af", "ebur128=peak=true:framelog=verbose", "-f", "f32le", "-ac", "2", "-ar", str(sr), "pipe:1"])
    lines = r.stderr.decode(errors="replace").splitlines()
    e, w, sample = count_log(lines)
    m["ffmpeg"] = {"rc": r.returncode, "errors": e, "warnings": w, "sample": sample}
    m["loudness"] = loudness(lines)
    x = np.frombuffer(r.stdout, dtype=np.float32)
    x = x[: len(x) // 2 * 2].reshape(-1, 2)
    m["signal"] = analyse(x, sr)
    del x, r

    codec = m["probe"]["codec"]
    if codec == "mp3":
        # (mpg123 -t was tried: it resyncs past damaged frames silently, so it adds nothing to mp3val)
        v = run(["mp3val", path]).stdout.decode(errors="replace").splitlines()
        m["mp3val"] = [re.sub(r'"[^"]*"', "", l).strip()[:160] for l in v if l.startswith(("WARNING", "INFO", "ERROR"))]
    elif codec == "flac":
        # FLAC stores an MD5 of the decoded audio: flac -t proves every sample is intact (when it is set)
        t = run(["flac", "-t", "-s", path])
        md5 = run(["metaflac", "--show-md5sum", path]).stdout.decode().strip()
        m["flac_test"] = {"rc": t.returncode, "out": t.stderr.decode(errors="replace").strip()[-300:],
                          "md5_set": bool(md5.strip("0"))}

    fp = None
    t = run(["fpcalc", "-raw", "-json", "-length", "120", path])
    try:
        j = json.loads(t.stdout)
        fp = np.array(j["fingerprint"], dtype=np.uint32).tobytes()
        m["fp_len"] = len(j["fingerprint"])
    except Exception:
        m["fp_error"] = t.stderr.decode(errors="replace").strip()[:200]
    return m, fp
