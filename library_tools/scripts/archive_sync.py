#!/usr/bin/env python3
"""Analyse the archive's new songs on this PC and write the results back through its analysis API.

Run it whenever; it does nothing if nothing is waiting.

  venv\\Scripts\\python scripts\\archive_sync.py                 analyse what is pending and write it back
  venv\\Scripts\\python scripts\\archive_sync.py --dry-run       same, but send nothing
  venv\\Scripts\\python scripts\\archive_sync.py --check         compare this PC's maths with what the server holds
  venv\\Scripts\\python scripts\\archive_sync.py --genre-affinities [--write-genre-affinities]

Settings come from music_archive/.env (or the environment):
  ANALYSIS_URL   e.g. https://archive.example/api/v1/analysis
  ANALYSIS_KEY   the analysis key (opens only the analysis endpoints)

What it does, following the API's own description (GET <ANALYSIS_URL>):
  1. refresh a local copy of the library: song list, embeddings and loudness/onset (only changes after the first run)
  2. download each pending song, analyse it exactly like the original library (analyze_audio.work_path)
  3. dials = percentile of the new song against the existing library; existing songs' dials are not touched
  4. POST /results in small batches and read each batch back
  5. sound-alike lists: for the new songs, and for every existing song that a new song now belongs in;
     POST /neighbors and read back
Songs whose audio cannot be decoded are remembered in work/sync/unanalysable.json and skipped next time
(--retry-failed tries them again).
"""
import argparse, base64, hashlib, json, os, sys, time
from collections import defaultdict
from multiprocessing import Pool
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
SYNC = ROOT / "work" / "sync"
NEIGHBORS = 30
PER_ARTIST = 4
DIALS = ["energy", "danceability", "happiness", "aggression", "acousticness", "electronic", "instrumental", "speech"]
RANGES = {"analyzed_seconds": (0.1, 100000), "loudness_db": (-150, 30), "peak_db": (-150, 30),
          "tempo_bpm": (20, 400), "brightness_hz": (0, 30000), "onset_strength": (0, 1000)}


def log(*a):
    print(*a, flush=True)


def load_env():
    f = ROOT / ".env"
    if f.exists():
        for line in f.read_text(encoding="utf-8").splitlines():
            if "=" in line and not line.lstrip().startswith("#"):
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip())


class Api:
    def __init__(self):
        import requests
        self.base = os.environ.get("ANALYSIS_URL", "").rstrip("/")
        key = os.environ.get("ANALYSIS_KEY", "")
        if not self.base or not key:
            sys.exit("ANALYSIS_URL and ANALYSIS_KEY must be set (music_archive/.env)")
        self.s = requests.Session()
        self.s.headers.update({"Authorization": "Bearer " + key, "User-Agent": "archive-analysis-sync"})

    def _req(self, method, path, **kw):
        url = path if path.startswith("http") else self.base + path
        for attempt in range(5):
            try:
                r = self.s.request(method, url, timeout=180, **kw)
            except Exception as e:  # network hiccup: wait and retry
                if attempt == 4:
                    raise
                time.sleep(3 * (attempt + 1))
                continue
            if r.status_code >= 500 and attempt < 4:
                time.sleep(3 * (attempt + 1))
                continue
            return r

    def get(self, path, **params):
        r = self._req("GET", path, params={k: v for k, v in params.items() if v is not None})
        if r.status_code != 200:
            sys.exit("GET %s -> %d %s" % (path, r.status_code, r.text[:300]))
        return r.json()

    def pages(self, path, key, limit, **params):
        after = None
        while True:
            d = self.get(path, limit=limit, after=after, **params)
            yield from d[key]
            after = d.get("next_after")
            if not after:
                return

    def post(self, path, body):
        r = self._req("POST", path, json=body)
        if r.status_code == 422:
            raise RuntimeError("server refused %s: %s" % (path, json.dumps(r.json().get("problems", r.text))[:1500]))
        if r.status_code not in (200, 201):
            raise RuntimeError("POST %s -> %d %s" % (path, r.status_code, r.text[:300]))
        return r.json()

    def download(self, url, dest):
        with self.s.get(url, stream=True, timeout=600) as r:
            if r.status_code != 200:
                raise RuntimeError("download HTTP %d" % r.status_code)
            with open(dest, "wb") as fh:
                for chunk in r.iter_content(1 << 20):
                    fh.write(chunk)


# ---------------------------------------------------------------- local copy of the library

def load_json(path, default):
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else default


def refresh_library(api):
    """Returns ids, emb (n x d float32, normalised), loud, onset, songs{id: song}. Keeps a cache in work/sync."""
    SYNC.mkdir(parents=True, exist_ok=True)
    state = load_json(SYNC / "state.json", {})
    if state.get("base") != api.base:  # a cache from another server is useless
        state = {"base": api.base}
    started = api.get("/status")["server_time"]

    emb, sig = {}, {}
    cache = SYNC / "library.npz"
    if cache.exists() and state.get("since"):
        z = np.load(cache, allow_pickle=False)
        ze, zl, zo = z["emb"], z["loud"], z["onset"]  # read each array once, not once per song
        for i, sid in enumerate(z["ids"].tolist()):
            emb[sid] = ze[i]
            sig[sid] = (float(zl[i]), float(zo[i]))
    since = state.get("since") if emb else None

    n = 0
    for e in api.pages("/embeddings", "embeddings", 2000, since=since):
        emb[e["song_id"]] = np.frombuffer(base64.b64decode(e["embedding_b64"]), dtype="<f4").copy()
        n += 1
        if n % 10000 == 0:
            log("  embeddings fetched: %d" % n)
    m = 0
    for f in api.pages("/features", "features", 5000, since=since):
        lo, on = f.get("loudness_db"), f.get("onset_strength")
        sig[f["song_id"]] = (np.nan if lo is None else float(lo), np.nan if on is None else float(on))
        m += 1
    songs = {s["id"]: s for s in api.pages("/songs", "songs", 2000)}
    log("library: %d songs on the server; fetched %d embeddings and %d feature rows%s"
        % (len(songs), n, m, " changed since " + since if since else " (full copy)"))

    # only songs that still exist and have both an embedding and a feature row belong to the library
    ids = sorted(i for i in emb if i in songs and i in sig)
    E = np.stack([emb[i] for i in ids]).astype(np.float32)
    E /= np.maximum(np.linalg.norm(E, axis=1, keepdims=True), 1e-9)
    loud = np.array([sig[i][0] for i in ids], dtype=np.float64)
    onset = np.array([sig[i][1] for i in ids], dtype=np.float64)
    np.savez(cache, ids=np.array(ids), emb=E, loud=loud, onset=onset)
    state["since"] = started
    (SYNC / "state.json").write_text(json.dumps(state), encoding="utf-8")
    for arr in (loud, onset):
        arr[np.isnan(arr)] = np.nanmedian(arr)
    return ids, E, loud, onset, songs


def text_vectors(model_name, phrases_by_dial):
    """One (towards - away) pair of phrase-vector groups per dial, from the model's text tower. Cached."""
    key = hashlib.sha1(json.dumps([model_name, phrases_by_dial], sort_keys=True).encode()).hexdigest()[:16]
    cache = SYNC / ("text_%s.npz" % key)
    flat, spans = [], {}
    for d in DIALS:
        p = phrases_by_dial[d]
        spans[d] = (len(flat), len(p["towards"]), len(p["away"]))
        flat += p["towards"] + p["away"]
    if cache.exists():
        return np.load(cache)["tv"], spans
    import torch
    from transformers import AutoTokenizer, ClapModel
    m = ClapModel.from_pretrained(model_name).eval()
    tok = AutoTokenizer.from_pretrained(model_name)
    with torch.no_grad():
        t = m.get_text_features(**tok(flat, padding=True, return_tensors="pt"))
    t = (t if torch.is_tensor(t) else t.pooler_output).numpy().astype(np.float32)
    t /= np.linalg.norm(t, axis=1, keepdims=True)
    if np.allclose(t[0], t[1], atol=1e-4):
        sys.exit("text vectors are all alike: wrong or broken model")
    np.savez(cache, tv=t)
    return t, spans


def raw_dials(E, tv, spans):
    sims = E @ tv.T
    return {d: sims[:, s:s + p].mean(axis=1) - sims[:, s + p:s + p + q].mean(axis=1) for d, (s, p, q) in spans.items()}


def percentile(x):
    r = np.empty(len(x), dtype=np.float64)
    r[np.argsort(x, kind="stable")] = np.arange(len(x))
    return r / max(len(x) - 1, 1)


def rank_in(sorted_lib, v):
    """Where new values v fall among the library's values, 0..1."""
    return np.clip(np.searchsorted(sorted_lib, v, side="left") / max(len(sorted_lib) - 1, 1), 0.0, 1.0)


class Scale:
    """The library's distribution of every dial, so a new song can be ranked against it."""

    def __init__(self, E, loud, onset, tv, spans):
        self.tv, self.spans = tv, spans
        raw = raw_dials(E, tv, spans)
        self.raw_sorted = {d: np.sort(raw[d]) for d in DIALS}
        self.loud_sorted, self.onset_sorted = np.sort(loud), np.sort(onset)
        self.lib = {d: percentile(raw[d]) for d in DIALS}
        self.blend_lib = 0.6 * self.lib["energy"] + 0.25 * percentile(loud) + 0.15 * percentile(onset)
        self.lib["energy"] = percentile(self.blend_lib)
        self.blend_sorted = np.sort(self.blend_lib)
        self.loud_median, self.onset_median = float(np.median(loud)), float(np.median(onset))

    def dials_for(self, e, loud, onset):
        raw = raw_dials(e, self.tv, self.spans)
        out = {d: rank_in(self.raw_sorted[d], raw[d]) for d in DIALS}
        blend = 0.6 * out["energy"] + 0.25 * rank_in(self.loud_sorted, loud) + 0.15 * rank_in(self.onset_sorted, onset)
        out["energy"] = rank_in(self.blend_sorted, blend)
        return out


# ---------------------------------------------------------------- sound-alike lists

def neighbor_lists(ids, E, songs, rows=None, must_contain=None):
    """Rule-based lists {song_id: [(id, score), ...]} for the given row indexes (default: all).
    must_contain: a set of row indexes; rows outside it are returned only if their list holds one of them."""
    import torch
    n = len(ids)
    artist = [((songs[s].get("artist") or {}).get("id")) or s for s in ids]
    rec = [songs[s].get("musicbrainz_recording_id") or "" for s in ids]
    tkey = [(artist[i], (songs[s].get("title") or "").lower()) for i, s in enumerate(ids)]
    dev = "cuda" if torch.cuda.is_available() else "cpu"
    T = torch.from_numpy(E).to(dev)
    K = min(NEIGHBORS * 8, n - 1)
    want = np.arange(n) if rows is None else np.asarray(sorted(rows))
    hot = None if must_contain is None else np.fromiter(must_contain, dtype=np.int64)
    out = {}
    for s0 in range(0, len(want), 2048):
        block = want[s0:s0 + 2048]
        sc, ix = torch.topk(T[torch.from_numpy(block).to(dev)] @ T.T, K + 1, dim=1)
        sc, ix = sc.cpu().numpy(), ix.cpu().numpy()
        keep = range(len(block))
        if hot is not None:  # cheap filter before the slow rule loop
            hit = np.isin(ix, hot).any(axis=1) | np.isin(block, hot)
            keep = np.nonzero(hit)[0]
        for r in keep:
            i = int(block[r])
            per, seen, lst = defaultdict(int), {tkey[i]}, []
            for score, j in zip(sc[r], ix[r]):
                j = int(j)
                if j == i or (rec[i] and rec[j] == rec[i]) or tkey[j] in seen or per[artist[j]] >= PER_ARTIST:
                    continue
                per[artist[j]] += 1
                seen.add(tkey[j])
                lst.append((ids[j], round(float(min(max(score, -1.0), 1.0)), 4)))
                if len(lst) >= NEIGHBORS:
                    break
            if hot is None or i in must_contain or any(index_of[x] in must_contain for x, _ in lst):
                out[ids[i]] = lst
    return out


index_of = {}


def genre_affinities(ids, lists, songs):
    genre = {s: (songs[s].get("genre") or {}).get("id") for s in ids}
    base = defaultdict(int)
    for g in genre.values():
        if g:
            base[g] += 1
    tagged = sum(base.values())
    pair, tot = defaultdict(int), defaultdict(int)
    for a, lst in lists.items():
        for b, _ in lst:
            ga, gb = genre[a], genre[b]
            if ga and gb:
                tot[ga] += 1
                pair[(ga, gb)] += 1
    by = defaultdict(list)
    for (ga, gb), c in pair.items():
        if ga == gb or base[ga] < 30 or base[gb] < 30:
            continue
        lift = (c / tot[ga]) / (base[gb] / tagged)
        if c >= 20 and lift >= 1.3:
            by[ga].append((lift, gb))
    for ga in list(by):
        for lift, gb in list(by[ga]):
            if all(g != ga for _, g in by[gb]):
                by[gb].append((lift, ga))
    return [{"genre_id": ga, "related_genre_id": gb, "score": round(lift, 3)}
            for ga, lst in by.items() for lift, gb in sorted(lst, reverse=True)[:10]]


# ---------------------------------------------------------------- analysing new songs

def analyse(api, todo, workers):
    """todo: pending songs. Returns ({id: (embedding, info)}, {id: error})."""
    import torch
    from transformers import ClapModel
    import analyze_audio as aa

    tmp = SYNC / "audio"
    tmp.mkdir(parents=True, exist_ok=True)
    jobs, errors = [], {}
    for k, s in enumerate(todo, 1):
        dest = tmp / ("%s.%s" % (s["id"], s.get("file_format") or "bin"))
        try:
            api.download(s["audio_url"], dest)
            jobs.append((s["id"], dest))
        except Exception as e:
            errors[s["id"]] = "download: %s" % e
        if k % 20 == 0:
            log("  downloaded %d/%d" % (k, len(todo)))

    model = ClapModel.from_pretrained(aa.MODEL, torch_dtype=torch.float16).to("cuda").eval()

    def embed(x, longer):
        with torch.no_grad():
            o = model.get_audio_features(input_features=torch.from_numpy(x).to("cuda", torch.float16),
                                         is_longer=torch.from_numpy(longer).to("cuda"))
        return (o if torch.is_tensor(o) else o.pooler_output).float().cpu().numpy()

    done = {}

    def take(res):
        song_id, err, info, feats = res
        if err:
            errors[song_id] = err
            return
        v = embed(feats[0], feats[1]).mean(axis=0)
        v /= max(np.linalg.norm(v), 1e-9)
        if not np.isfinite(v).all():
            errors[song_id] = "embedding is not finite"
            return
        done[song_id] = (v.astype(np.float32), info)

    if len(jobs) <= 4:
        for j in jobs:
            take(aa.work_path(j))
    else:
        with Pool(min(workers, len(jobs)), initializer=aa._init) as pool:
            for res in pool.imap_unordered(aa.work_path, jobs, chunksize=1):
                take(res)
    for _, p in jobs:
        p.unlink(missing_ok=True)
    return done, errors


def post_results(api, model_name, batch):
    api.post("/results", {"model": model_name, "replace": False, "songs": batch})
    ids = ",".join(b["song_id"] for b in batch)
    back = {f["song_id"]: f for f in api.get("/features", ids=ids, limit=len(batch))["features"]}
    vecs = {e["song_id"]: np.frombuffer(base64.b64decode(e["embedding_b64"]), dtype="<f4")
            for e in api.get("/embeddings", ids=ids, limit=len(batch))["embeddings"]}
    for b in batch:
        f, v = back.get(b["song_id"]), vecs.get(b["song_id"])
        if f is None or v is None:
            raise RuntimeError("read-back: %s is missing after the write" % b["song_id"])
        for k, x in b["features"].items():
            if abs(float(f[k]) - x) > 2e-3 * max(1.0, abs(x)):
                raise RuntimeError("read-back: %s %s sent %s, server has %s" % (b["song_id"], k, x, f[k]))
        sent = np.frombuffer(base64.b64decode(b["embedding_b64"]), dtype="<f4")
        if np.abs(sent - v).max() > 1e-4:
            raise RuntimeError("read-back: embedding of %s differs" % b["song_id"])


def post_neighbors(api, lists):
    items = [{"song_id": s, "neighbors": [{"id": i, "score": sc} for i, sc in lst]} for s, lst in lists.items() if lst]
    for s0 in range(0, len(items), 200):
        chunk = items[s0:s0 + 200]
        api.post("/neighbors", {"lists": chunk})
        back = read_neighbors(api, [c["song_id"] for c in chunk])
        for c in chunk:
            if [x["id"] for x in c["neighbors"]] != [i for i, _ in back.get(c["song_id"], [])]:
                raise RuntimeError("read-back: neighbour list of %s differs" % c["song_id"])
    return len(items)


def read_neighbors(api, ids):
    out = {}
    for s0 in range(0, len(ids), 200):
        d = api.get("/neighbors", ids=",".join(ids[s0:s0 + 200]))
        rows = d.get("lists") or d.get("neighbors") or []
        if isinstance(rows, dict):
            rows = [{"song_id": k, "neighbors": v} for k, v in rows.items()]
        for row in rows:
            out[row["song_id"]] = [(x["id"], x["score"]) for x in row["neighbors"]]
    return out


# ---------------------------------------------------------------- commands

def check(api, ids, E, songs, scale):
    """Does this PC reproduce what the server already holds? Run before trusting a first write."""
    rng = np.random.default_rng(1)
    pick = [ids[i] for i in sorted(rng.choice(len(ids), 200, replace=False))]
    stored = {f["song_id"]: f for f in api.get("/features", ids=",".join(pick), limit=200)["features"]}
    log("dials, 200 random library songs: largest difference from the stored value")
    for d in DIALS:
        diff = [abs(scale.lib[d][index_of[s]] - stored[s][d]) for s in pick]
        log("  %-13s max %.4f   mean %.4f" % (d, max(diff), float(np.mean(diff))))
    mine = neighbor_lists(ids, E, songs, rows=[index_of[s] for s in pick])
    theirs = read_neighbors(api, pick)
    same = sum(1 for s in pick if [i for i, _ in mine[s]] == [i for i, _ in theirs.get(s, [])])
    overlap = np.mean([len({i for i, _ in mine[s]} & {i for i, _ in theirs.get(s, [])}) / max(len(mine[s]), 1) for s in pick])
    log("sound-alike lists: %d of 200 identical in order; average overlap %.1f%%" % (same, 100 * overlap))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true", help="analyse but send nothing")
    ap.add_argument("--check", action="store_true", help="compare local maths with the server's stored values and stop")
    ap.add_argument("--limit", type=int, default=0, help="analyse at most N pending songs")
    ap.add_argument("--batch", type=int, default=25, help="songs per write")
    ap.add_argument("--workers", type=int, default=12)
    ap.add_argument("--retry-failed", action="store_true", help="try songs that failed to decode before")
    ap.add_argument("--genre-affinities", action="store_true", help="recompute genre adjacency and compare with the server")
    ap.add_argument("--write-genre-affinities", action="store_true", help="...and replace the server's table")
    a = ap.parse_args()
    load_env()
    api = Api()

    desc = api.get("")
    model_name = desc["library"]["analysis_model"]
    st = api.get("/status")
    log("server: %d songs, %d analysed, %d awaiting; model %s"
        % (st["songs"], st["songs_analysed"], st["songs_awaiting_analysis"], model_name))
    import analyze_audio as aa
    if model_name != aa.MODEL:
        sys.exit("the server's model is %s but analyze_audio.py uses %s" % (model_name, aa.MODEL))
    if not (a.check or a.genre_affinities or st["songs_awaiting_analysis"]):
        log("nothing to do")
        return

    ids, E, loud, onset, songs = refresh_library(api)
    index_of.clear()
    index_of.update({s: i for i, s in enumerate(ids)})
    if E.shape[1] != desc["library"]["embedding_dimensions"]:
        sys.exit("embedding size mismatch")
    tv, spans = text_vectors(model_name, desc["definitions"]["dials"]["phrases"])
    scale = Scale(E, loud, onset, tv, spans)

    if a.check:
        check(api, ids, E, songs, scale)
        return

    if a.genre_affinities:
        lists = neighbor_lists(ids, E, songs)
        mine = genre_affinities(ids, lists, songs)
        theirs = api.get("/genre_affinities")["affinities"]
        A = {(x["genre_id"], x["related_genre_id"]) for x in mine}
        B = {(x["genre_id"], x["related_genre_id"]) for x in theirs}
        log("genre adjacency: computed %d pairs, server has %d, in common %d" % (len(A), len(B), len(A & B)))
        if a.write_genre_affinities and not a.dry_run:
            api.post("/genre_affinities", {"affinities": mine, "allow_shrink": False})
            log("genre adjacency table replaced")
        return

    # ---- pending songs
    failed_path = SYNC / "unanalysable.json"
    failed = load_json(failed_path, {})
    pending = list(api.pages("/pending", "songs", 500))
    waiting = {s["id"] for s in pending}
    failed = {k: v for k, v in failed.items() if k in waiting}  # forget songs since analysed or deleted
    todo = [s for s in pending if a.retry_failed or failed.get(s["id"], {}).get("updated_at") != s["updated_at"]]
    log("pending %d, of which %d failed before and are skipped" % (len(pending), len(pending) - len(todo)))
    if a.limit:
        todo = todo[:a.limit]
    if not todo:
        log("nothing new to analyse")
        return

    by_id = {s["id"]: s for s in todo}
    done, errors = analyse(api, todo, a.workers)
    for sid, err in errors.items():
        failed[sid] = {"error": err, "updated_at": by_id[sid]["updated_at"], "title": by_id[sid].get("title")}
        log("  cannot analyse: %s - %s" % (by_id[sid].get("title"), err[:120]))
    if not a.dry_run:
        failed_path.write_text(json.dumps(failed, indent=1), encoding="utf-8")
    if not done:
        log("no song could be analysed")
        return

    new_ids = sorted(done)
    NE = np.stack([done[s][0] for s in new_ids])
    nl = np.array([done[s][1]["loudness_db"] for s in new_ids], dtype=np.float64)
    no = np.array([done[s][1]["onset_strength"] for s in new_ids], dtype=np.float64)
    dial = scale.dials_for(NE, nl, no)
    payload = []
    for k, sid in enumerate(new_ids):
        info = done[sid][1]
        feats = {d: round(float(dial[d][k]), 4) for d in DIALS}
        for name, (lo, hi) in RANGES.items():
            v = info.get(name)
            if v is not None and np.isfinite(v) and lo <= v <= hi:
                feats[name] = float(v)
        payload.append({"song_id": sid, "features": feats,
                        "embedding_b64": base64.b64encode(done[sid][0].astype("<f4").tobytes()).decode()})
        s = by_id[sid]
        log("  %-28.28s %-34.34s energy %.2f dance %.2f happy %.2f speech %.2f"
            % ((s.get("artist") or {}).get("name") or "?", s.get("title") or "?", feats["energy"],
               feats["danceability"], feats["happiness"], feats["speech"]))

    # ---- lists, over the library plus the new songs
    all_ids = ids + new_ids
    allE = np.concatenate([E, NE])
    for s in new_ids:
        songs[s] = by_id[s]
    index_of.update({s: i for i, s in enumerate(all_ids)})
    new_rows = set(range(len(ids), len(all_ids)))
    lists = neighbor_lists(all_ids, allE, songs, must_contain=new_rows)
    touched = len(lists) - len(new_ids)
    log("%d new songs analysed; %d existing songs gain one of them as a neighbour" % (len(new_ids), touched))

    if a.dry_run:
        log("DRY RUN: nothing sent")
        return
    for s0 in range(0, len(payload), a.batch):
        post_results(api, model_name, payload[s0:s0 + a.batch])
        log("  results written and read back: %d/%d" % (min(s0 + a.batch, len(payload)), len(payload)))
    sent = post_neighbors(api, lists)
    log("  sound-alike lists written and read back: %d" % sent)
    st = api.get("/status")
    log("server now: %d analysed, %d awaiting" % (st["songs_analysed"], st["songs_awaiting_analysis"]))


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    main()
