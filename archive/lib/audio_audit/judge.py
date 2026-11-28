"""Turn measurements (measure.py) into verdicts, scores, duplicate groups and a ranking of copies.

Shared by the library audit (library_tools/audit/score.py, incoming.py) and the Drop Box (cli.py).
Changing RULES changes verdicts without decoding anything again; raise SCORE_VERSION when it does.

Every file gets:
  verdict   bad      broken in a way you hear, or unreadable: replace it
            flawed   plays, but has a fault: a few damaged frames, channels out of phase, a "lossless"
                     file made from a lossy one, cut off at the end: replace it when a better copy turns up
            weak     intact, but low fidelity: low bitrate, or the music stops well below what its bitrate
                     should carry (made from a lower-quality copy, or an old encoder)
            ok
  problems  the reasons, in words
  quality   0-100. Intact real lossless is 100; lossy copies score by how far up the spectrum they
            really go and their bitrate; flaws cost points.

Copies of one recording are found by Chromaprint fingerprint (bit error rate under RULES["fp_max_ber"],
lengths agreeing) and ranked by strength_of: intact beats weak beats flawed beats bad, then real
lossless, then resolution (hi-res over CD), then real frequency content, then bitrate.
The app's CopyRanking (Ruby) mirrors strength_of; keep the two in step.
"""
import os, re, sys
from collections import defaultdict, Counter

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))   # python -I leaves the script dir off the path
from textnorm import norm_name, COMPILATION  # noqa: E402,F401  (every script and language)

SCORE_VERSION = 1

RULES = {
    # damaged spots: a burst far past full scale, much louder than the music around it
    "burst_peak": 1.6, "burst_ms": 4.0, "burst_ratio": 1.8,
    # a digital silence inside the music, with music on both sides at least this loud
    "dropout_side_db": -30,
    # normal-decode errors that mean damaged frames in the middle of the song (with mp3val resyncs)
    "corrupt_errors_bad": 5, "corrupt_errors_flawed": 3,
    # an encoder's lowpass: the spectrum falls at least this many dB within ~1.5 kHz
    "lowpass_steep_db": 28,
    # a lossy file is "made from a lower-quality copy" when its lowpass is this far below what its own
    # bitrate would produce
    "transcode_margin_khz": 1.25,
    # a lossless file whose lowpass sits at or below this came from a lossy file
    "fake_lossless_khz": 20.0,
    # low quality: the music stops below this
    "low_khz": 15.0,
    # the last 100 ms still this loud: probably cut off
    "cut_end_db": -12,
    "truncated_ratio": 0.90,
    # fingerprints: same recording below this bit error rate; same version when lengths agree within
    # max(dup_dur_s, dup_dur_frac * length)
    "fp_max_ber": 0.20, "fp_min_overlap": 160, "fp_max_shift": 24,
    "dup_dur_s": 4.0, "dup_dur_frac": 0.03,
}

# the highest frequency an encoder keeps at a given bitrate (a little under the usual lowpass, so an
# honest encode is never called a transcode)
EXPECTED_KHZ = {
    "mp3": [(0, 8.0), (64, 10.5), (96, 14.0), (128, 15.5), (160, 16.5), (192, 18.0), (224, 18.5), (256, 19.0), (320, 19.5)],
    "aac": [(0, 8.0), (64, 12.0), (96, 14.5), (128, 15.5), (192, 17.5), (256, 18.5), (320, 19.0)],
    "vorbis": [(0, 8.0), (96, 14.0), (128, 15.5), (192, 17.5), (256, 18.5), (320, 19.0)],
    "opus": [(0, 8.0), (96, 18.0), (128, 19.0)],
}
LOSSLESS = {"flac", "alac", "pcm_s16le", "pcm_s24le", "wavpack", "ape"}


def expected_khz(codec, kbps):
    table = EXPECTED_KHZ.get(codec, EXPECTED_KHZ["aac"])
    out = table[0][1]
    for k, v in table:
        if kbps >= k - 8:
            out = v
    return out


def mmss(t):
    t = int(t)
    return f"{t // 60}:{t % 60:02d}"


def lowpass(bands):
    """(cutoff kHz, steepness dB) from the 250 Hz band profile."""
    idx = [i for i, v in enumerate(bands or []) if v is not None and v > -45]
    if not idx:
        return 0.0, 0.0
    c = max(idx)
    lo = [v for v in bands[max(0, c - 6):c - 2] if v is not None]
    hi = [v for v in bands[c + 1:c + 5] if v is not None]
    steep = (sum(lo) / len(lo) - sum(hi) / len(hi)) if lo and hi else 0.0
    return c * 0.25, round(steep, 1)


def evaluate(row, m):
    """verdict, problems [(level, text)], notes [text], numbers."""
    R = RULES
    problems, notes = [], []
    out = {"verdict": "ok", "quality": 0, "eff_khz": None, "lossless": False, "codec": None, "kbps": None}
    if row["status"] != "ok":
        return {**out, "verdict": "bad", "problems": [("bad", f"could not be read ({row['status']}: {row['error']})")], "notes": []}
    p = m.get("probe")
    if not p:
        return {**out, "verdict": "bad", "problems": [("bad", "no audio stream")], "notes": []}
    s = m.get("signal", {})
    codec = p["codec"]; kbps = p["stream_kbps"] or p["format_kbps"]
    out.update(codec=codec, kbps=kbps)
    if row["md5_ok"] == 0:
        problems.append(("bad", "file changed on disk since upload (checksum mismatch)"))
    if s.get("too_short") or s.get("silent"):
        problems.append(("bad", "silent" if s.get("silent") else "almost no audio"))
    ff = m.get("ffmpeg", {})
    if ff.get("rc"):
        problems.append(("bad", f"decoder failed: {'; '.join(ff.get('sample', []))[:120]}"))

    bursts = [e for e in s.get("overshoots", []) if e["peak"] >= R["burst_peak"] and e["ms"] >= R["burst_ms"]
              and e["peak"] >= R["burst_ratio"] * (e["ctx_p99"] or 0.01)]
    if bursts:
        at = ", ".join(mmss(e["t"]) for e in sorted(bursts, key=lambda e: e["t"])[:6])
        problems.append(("bad", f"{len(bursts)} damaged spot{'s' * (len(bursts) > 1)} (loud blowouts) at {at}"))
    drops = [g for g in s.get("gaps", []) if min(g["before_db"], g["after_db"]) > R["dropout_side_db"]]
    if drops:
        problems.append(("bad", f"audio drops out at {', '.join(mmss(g['t']) for g in drops[:6])}"))

    resync = [x for x in m.get("mp3val", []) if "resynchronized" in x or "Non-layer-III" in x]
    errs = ff.get("errors", 0)
    # fpcalc gives up at the first frame it cannot decode: a fingerprint far shorter than the audio
    # says where the damage starts
    dec0 = s.get("decoded_dur") or 0
    fp_len = m.get("fp_len")
    if errs and fp_len is not None and dec0 > 10 and fp_len < 0.6 * min(dec0, 120) * 7.8:
        problems.append(("bad" if errs >= R["corrupt_errors_flawed"] else "flawed",
                         f"corrupt data from about {mmss(fp_len / 7.8)} (decoders stumble there)"))
    elif resync or (codec != "mp3" and errs):
        if errs >= R["corrupt_errors_bad"]:
            problems.append(("bad", f"corrupt frames in the middle of the song ({errs} decode errors)"))
        elif errs >= R["corrupt_errors_flawed"]:
            problems.append(("flawed", f"a few damaged frames ({errs} decode errors, {len(resync)} resyncs)"))
        else:
            notes.append(f"stream hiccup ({errs} decode errors, {len(resync)} resyncs) players skip over")
    elif errs >= R["corrupt_errors_bad"]:
        problems.append(("flawed", f"{errs} decode errors"))
    elif errs > 2:
        notes.append(f"{errs} decode errors (usually junk at the end)")
    ft = m.get("flac_test")
    if ft and ft["rc"]:
        problems.append(("bad", f"FLAC self-test failed: {ft['out'][-100:]}"))
    if ft and not ft.get("md5_set", True):
        notes.append("FLAC has no stored checksum")

    dbdur = m.get("db", {}).get("duration") or 0
    dec = s.get("decoded_dur") or 0
    if dbdur > 10 and dec < R["truncated_ratio"] * dbdur:
        problems.append(("bad", f"truncated: plays {mmss(dec)} of {mmss(dbdur)}"))
    if s.get("last_100ms_db", -99) > R["cut_end_db"]:
        problems.append(("flawed", f"ends abruptly (last instant at {s['last_100ms_db']} dB): probably cut off"))
    elif s.get("last_100ms_db", -99) > -20:
        notes.append("ends loud (a segue, or cut off)")

    # real quality
    cut, steep = lowpass(s.get("bands_250hz"))
    limited = steep >= R["lowpass_steep_db"]
    eff = min(cut, 21.0)
    lossless = codec in LOSSLESS
    if lossless and limited and cut <= R["fake_lossless_khz"]:
        problems.append(("flawed", f"lossless file made from a lossy copy (stops sharply at {cut:g} kHz)"))
        lossless = False
    elif not lossless and ((limited and eff < R["low_khz"]) or 0 < kbps < 96):
        # (an old recording can have nothing up there at all: only a sharp encoder cutoff counts)
        problems.append(("weak", f"low quality: stops at {eff:g} kHz ({kbps} kbps)"))
    elif not lossless and limited and cut < expected_khz(codec, kbps) - R["transcode_margin_khz"]:
        if cut < expected_khz(codec, kbps) - 3.5:
            problems.append(("weak", f"made from a lower-quality copy: a {kbps} kbps file that stops at {cut:g} kHz"))
        else:
            problems.append(("weak", f"sounds like a smaller file: {kbps} kbps but stops at {cut:g} kHz "
                                     f"(an old encoder, or made from a lower-quality copy)"))
    # resolution only counts between real lossless copies: 24-bit / 48 kHz and up is a hi-res master
    res = (p.get("bits") or 16, p.get("sample_rate") or 44100) if lossless else (0, 0)
    out.update(eff_khz=eff, lossless=lossless, cutoff=cut, steep=steep, res=res)

    # notes that never change the verdict
    if s.get("lr_identical"):
        notes.append("mono (both channels identical)")
    if (s.get("lr_corr") or 0) < -0.5:
        problems.append(("flawed", f"channels out of phase (correlation {s['lr_corr']})"))
    if any(abs(d) > 0.02 for d in s.get("dc", [])):
        notes.append(f"DC offset {s['dc']}")
    if s.get("clip_runs", 0) > 200 or s.get("over_full_scale", 0) > 5000:
        notes.append("heavily clipped master")
    hdr = [x for x in m.get("mp3val", []) if "Xing" in x or "VBR header" in x]
    if hdr:
        notes.append("MP3 header lists the wrong length (fixable without re-encoding)")
    if any("garbage at the end" in x.lower() for x in m.get("mp3val", [])):
        notes.append("junk after the last frame (harmless)")
    se = m.get("ffmpeg_strict", {}).get("errors", 0)
    if se and not errs:
        notes.append(f"strict decoder complains ({se}), players don't")

    levels = {l for l, _ in problems}
    verdict = next((v for v in ("bad", "flawed", "weak") if v in levels), "ok")
    if lossless:
        q = 100.0
    else:
        q = 30 + 50 * min(1, max(0, (eff - 14) / 6)) + 15 * min(1, max(0, (kbps - 96) / 224))
    q -= 15 * min(2, sum(1 for l, _ in problems if l == "flawed"))
    q -= 5 * min(2, sum(1 for l, _ in problems if l == "weak"))
    if verdict == "bad":
        q = min(q, 20)
    out.update(verdict=verdict, quality=round(max(q, 0)), problems=problems, notes=notes)
    return out


# ---------------------------------------------------------------- duplicates

def ber(a, b, max_shift, min_overlap):
    best = 1.0
    for sh in range(-max_shift, max_shift + 1):
        x, y = (a[sh:], b) if sh >= 0 else (a, b[-sh:])
        n = min(len(x), len(y))
        if n < min_overlap:
            continue
        e = np.bitwise_count(np.bitwise_xor(x[:n], y[:n])).sum() / (32.0 * n)
        best = min(best, e)
    return best


def find_duplicates(keys, fps, durs, extra_pairs=()):
    R = RULES
    # index a sample of each file's frames; look up every frame of each file, so copies that are
    # shifted by any number of frames still meet
    index = defaultdict(list)
    for i, fp in enumerate(fps):
        if fp is None or len(fp) < 40:
            continue
        for v in set(fp[16:420:4].tolist()):
            index[v].append(i)
    index = {v: L for v, L in index.items() if len(L) <= 80}   # values every quiet intro shares
    pair_hits = Counter()
    for i, fp in enumerate(fps):
        if fp is None or len(fp) < 40:
            continue
        seen = Counter()
        for v in set(fp[:460].tolist()):
            for j in index.get(v, ()):
                if j > i:
                    seen[j] += 1
        for j, c in seen.items():
            pair_hits[(i, j)] += c
    # same artist + title (tags) are always compared too: remasters can share few exact frames.
    # The fingerprint still decides.
    for i, j in extra_pairs:
        if fps[i] is not None and fps[j] is not None:
            pair_hits[(min(i, j), max(i, j))] += 3
    parent = list(range(len(keys)))
    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]; i = parent[i]
        return i
    same, related = [], []
    for (i, j), hits in pair_hits.items():
        if hits < 3:
            continue
        overlap = min(R["fp_min_overlap"], int(0.8 * min(len(fps[i]), len(fps[j]))))
        e = ber(fps[i], fps[j], R["fp_max_shift"], overlap)
        if e > R["fp_max_ber"]:
            continue
        di, dj = durs[i], durs[j]
        if abs(di - dj) <= max(R["dup_dur_s"], R["dup_dur_frac"] * max(di, dj)):
            same.append((i, j, e))
            parent[find(i)] = find(j)
        else:
            related.append((i, j, e))
    groups = defaultdict(list)
    for i in range(len(keys)):
        groups[find(i)].append(i)
    return [g for g in groups.values() if len(g) > 1], same, related



# ---------------------------------------------------------------- ranking copies of one recording
# shared with incoming.py, so an import is judged by exactly the rules the dedup uses

RANK = {"ok": 3, "weak": 2, "flawed": 1, "bad": 0}


def kbps_tier(k):
    return 3 if k >= 256 else 2 if k >= 192 else 1 if k >= 128 else 0


def album_counts(songs):
    album_songs, album_artist_songs = Counter(), Counter()
    for so in songs:
        album_songs[so.get("album_id")] += 1
        album_artist_songs[(so.get("album_id"), so.get("artist_id"))] += 1
    return album_songs, album_artist_songs


def album_pref(so, album_songs, album_artist_songs):
    """the artist's share of the album, less a penalty for hits packages and compilations"""
    share = album_artist_songs[(so.get("album_id"), so.get("artist_id"))] / max(1, album_songs[so.get("album_id")])
    return round(share - (0.6 if COMPILATION.search(so.get("album") or "") else 0), 2)


def strength_of(ev, pref, plays=0, key=""):
    """sort key, higher is better. Above ~19.5 kHz differences are inaudible: there bitrate and the album decide."""
    return (RANK[ev["verdict"]], ev["lossless"], tuple(ev.get("res") or (0, 0)),
            min(19.5, round((ev["eff_khz"] or 0) * 2) / 2), kbps_tier(ev["kbps"] or 0),
            pref, ev["kbps"] or 0, plays, key)


def why_worse(b, e):
    """why copy b (an evaluate() result) beats copy e, in words"""
    reasons = []
    if RANK[b["verdict"]] > RANK[e["verdict"]]: reasons.append(f"the other copy is {e['verdict']}")
    if b["lossless"] and not e["lossless"]: reasons.append("lossless against lossy")
    elif b["lossless"] and tuple(b.get("res") or ()) > tuple(e.get("res") or ()):
        (bb, bs), (eb, es) = b["res"], e["res"]
        reasons.append(f"{bb}-bit/{bs / 1000:g} kHz against {eb}-bit/{es / 1000:g} kHz")
    if min(19.5, b["eff_khz"] or 0) > min(19.5, e["eff_khz"] or 0) + 0.4:
        reasons.append(f"goes to {b['eff_khz']:g} kHz against {e['eff_khz']:g}")
    if not reasons and kbps_tier(b["kbps"] or 0) > kbps_tier(e["kbps"] or 0):
        reasons.append(f"{b['kbps']} kbps against {e['kbps']}")
    return reasons
