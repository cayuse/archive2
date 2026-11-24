#!/usr/bin/env python3
"""Turn the raw analysis (work/audio/shard_*.npz + features.jsonl) into what the site loads:

  work/audio/out/features.tsv    one row per song: signal features + 0..1 steering dials
  work/audio/out/neighbors.tsv   song_id, neighbor_id, rank, score   (nearest songs by sound)
  work/audio/out/embeddings.tsv  song_id, {v1,v2,...}                 (Postgres real[] literal)

Dials are text-steered: each is "how much closer to these phrases than to those", turned into a
percentile within the library so 0.9 always means "more than 90% of the archive".

  venv\\Scripts\\python scripts\\build_vectors.py [--neighbors 30]
"""
import argparse, glob, json
from collections import defaultdict
from pathlib import Path

import numpy as np
import torch

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "work" / "audio"
OUT = SRC / "out"
MODEL = "laion/larger_clap_music_and_speech"

DIALS = {  # name: (phrases it should move towards, phrases it should move away from)
    "energy": (["high energy music, loud, fast and intense", "an energetic, driving, powerful track"],
               ["calm, quiet, slow and gentle music", "a soft, relaxing, mellow track"]),
    "danceability": (["dance music with a strong steady beat", "a groovy track that makes you want to dance"],
                     ["music with no beat, free rhythm", "ambient or orchestral music you cannot dance to"]),
    "happiness": (["happy, cheerful, uplifting music", "a joyful feel-good song"],
                  ["sad, melancholic, sorrowful music", "a dark, depressing, gloomy song"]),
    "aggression": (["aggressive, angry, heavy music", "harsh distorted guitars and shouting"],
                   ["gentle, tender, peaceful music", "a sweet soft lullaby"]),
    "acousticness": (["acoustic music played on acoustic instruments", "unplugged acoustic guitar or piano"],
                     ["electronic music made with synthesizers", "heavily produced electric and electronic sound"]),
    "electronic": (["electronic music with synthesizers and drum machines", "techno, house or electro"],
                   ["a live band with guitars, bass and drums", "acoustic or orchestral instruments"]),
    "instrumental": (["instrumental music with no vocals", "music without any singing"],
                     ["a song with a lead singer", "vocals and singing"]),
    "speech": (["a person speaking, spoken word", "audiobook narration, someone talking without music"],
               ["music", "a song with instruments"]),
}


def load():
    ids, emb = [], []
    for f in sorted(glob.glob(str(SRC / "shard_*.npz"))):
        z = np.load(f)
        ids += z["ids"].tolist()
        emb.append(z["emb"].astype(np.float32))
    emb = np.concatenate(emb)
    emb /= np.maximum(np.linalg.norm(emb, axis=1, keepdims=True), 1e-9)
    feats = {}
    for l in open(SRC / "features.jsonl", encoding="utf-8"):
        j = json.loads(l)
        feats[j["song_id"]] = j
    info = {}
    for l in open(ROOT / "work" / "song_info.tsv", encoding="utf-8"):
        p = l.rstrip("\n").split("\t")
        info[p[0]] = p
    return ids, emb, feats, info


def text_vectors(phrases):
    from transformers import AutoTokenizer, ClapModel
    m = ClapModel.from_pretrained(MODEL).eval()
    tok = AutoTokenizer.from_pretrained(MODEL)
    with torch.no_grad():
        t = m.get_text_features(**tok(phrases, padding=True, return_tensors="pt"))
    t = (t if torch.is_tensor(t) else t.pooler_output).numpy().astype(np.float32)
    return t / np.linalg.norm(t, axis=1, keepdims=True)


def percentile(x):
    r = np.empty(len(x), dtype=np.float64)
    r[np.argsort(x, kind="stable")] = np.arange(len(x))
    return r / max(len(x) - 1, 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--neighbors", type=int, default=30)
    ap.add_argument("--per-artist", type=int, default=4, help="max neighbours by one artist")
    a = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    ids, emb, feats, info = load()
    n = len(ids)
    print("songs with vectors:", n)

    # ---- dials
    names = list(DIALS)
    phrases, spans = [], []
    for k in names:
        pos, neg = DIALS[k]
        spans.append((len(phrases), len(pos), len(neg)))
        phrases += pos + neg
    tv = text_vectors(phrases)
    sims = emb @ tv.T
    dial = {}
    for k, (s, n_pos, n_neg) in zip(names, spans):
        dial[k] = percentile(sims[:, s:s + n_pos].mean(axis=1) - sims[:, s + n_pos:s + n_pos + n_neg].mean(axis=1))
    # energy also listens to the signal itself: loudness and onset strength
    loud = np.array([feats.get(i, {}).get("loudness_db", np.nan) for i in ids], dtype=np.float64)
    onset = np.array([feats.get(i, {}).get("onset_strength", np.nan) for i in ids], dtype=np.float64)
    for arr in (loud, onset):
        arr[np.isnan(arr)] = np.nanmedian(arr)
    dial["energy"] = percentile(0.6 * dial["energy"] + 0.25 * percentile(loud) + 0.15 * percentile(onset))

    cols = ["analyzed_seconds", "loudness_db", "peak_db", "tempo_bpm", "brightness_hz", "onset_strength"]
    with open(OUT / "features.tsv", "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\t".join(["song_id"] + cols + names) + "\n")
        for i, sid in enumerate(ids):
            f = feats.get(sid, {})
            fh.write("\t".join([sid] + [str(f.get(c, "")) for c in cols] + ["%.4f" % dial[k][i] for k in names]) + "\n")

    # ---- neighbours (GPU), skipping other copies of the same recording and capping each artist
    blank = [""] * 10
    artist = [info.get(s, blank)[6] or s for s in ids]
    rec = [info.get(s, blank)[7] for s in ids]
    title_key = [(artist[i], info.get(s, blank)[2].lower()) for i, s in enumerate(ids)]
    dev = "cuda" if torch.cuda.is_available() else "cpu"
    E = torch.from_numpy(emb).to(dev)
    K = min(a.neighbors * 8, n - 1)
    rows = 0
    with open(OUT / "neighbors.tsv", "w", encoding="utf-8", newline="\n") as fh:
        for s0 in range(0, n, 2048):
            sc, ix = torch.topk(E[s0:s0 + 2048] @ E.T, K + 1, dim=1)
            sc, ix = sc.cpu().numpy(), ix.cpu().numpy()
            for r in range(sc.shape[0]):
                i = s0 + r
                per, seen, rank = defaultdict(int), {title_key[i]}, 0
                for score, j in zip(sc[r], ix[r]):
                    if j == i or (rec[i] and rec[j] == rec[i]) or title_key[j] in seen:
                        continue
                    if per[artist[j]] >= a.per_artist:
                        continue
                    per[artist[j]] += 1
                    seen.add(title_key[j])
                    fh.write("%s\t%s\t%d\t%.4f\n" % (ids[i], ids[j], rank, score))
                    rank += 1
                    rows += 1
                    if rank >= a.neighbors:
                        break
    # ---- adjacent genres, learned from the neighbour links: genre A is adjacent to B when A's songs
    # have B-tagged neighbours clearly more often than chance (lift), and often enough to matter (share)
    genre = [(info.get(s, blank) + blank)[9] for s in ids]
    index = {s: i for i, s in enumerate(ids)}
    base = defaultdict(int)
    for g in genre:
        if g:
            base[g] += 1
    tagged = sum(base.values())
    pair, tot = defaultdict(int), defaultdict(int)
    for l in open(OUT / "neighbors.tsv", encoding="utf-8"):
        a, b, _, _ = l.split("\t")
        ga, gb = genre[index[a]], genre[index[b]]
        if ga and gb:
            tot[ga] += 1
            pair[(ga, gb)] += 1
    by = defaultdict(list)
    for (ga, gb), c in pair.items():
        if ga == gb or base[ga] < 30 or base[gb] < 30:
            continue
        share = c / tot[ga]
        lift = share / (base[gb] / tagged)
        # big genres (Country, Rock) mostly neighbour themselves, so the bar is "clearly above chance
        # on a real number of links", not a large share
        if c >= 20 and lift >= 1.3:
            by[ga].append((lift, gb))
    # adjacency runs both ways: if Bluegrass leans on Country, Country may wander into Bluegrass
    for ga in list(by):
        for lift, gb in list(by[ga]):
            if all(g != ga for _, g in by[gb]):
                by[gb].append((lift, ga))
    aff = 0
    with open(OUT / "genre_affinity.tsv", "w", encoding="utf-8", newline="\n") as fh:
        for ga, lst in by.items():
            for lift, gb in sorted(lst, reverse=True)[:10]:
                fh.write("%s\t%s\t%.3f\n" % (ga, gb, lift))
                aff += 1
    gname = {}
    for p in info.values():
        if len(p) > 9 and p[9]:
            gname[p[9]] = p[4]
    print("genre adjacency rows:", aff)
    for want in ("Country", "Rock", "Jazz", "Classical", "Hip Hop/Rap", "Metal", "Blues", "Reggae"):
        gid = next((k for k, v in gname.items() if v == want), None)
        if gid in by:
            print("  %s -> %s" % (want, ", ".join("%s (%.1fx)" % (gname.get(g, "?"), l) for l, g in sorted(by[gid], reverse=True)[:8])))

    with open(OUT / "embeddings.tsv", "w", encoding="utf-8", newline="\n") as fh:
        for sid, v in zip(ids, emb):
            fh.write(sid + "\t{" + ",".join("%.5f" % x for x in v) + "}\n")
    print("wrote features %d, neighbour rows %d, embeddings %d -> %s" % (n, rows, n, OUT))

    # ---- eyeball
    def name(i):
        p = info.get(ids[i], blank)
        return ("%s - %s [%s]" % (p[1], p[2], p[4]))[:70]
    for k in names:
        o = np.argsort(dial[k])
        print("\n%s  HIGH: %s" % (k, " | ".join(name(i) for i in o[-3:][::-1])))
        print("%s   LOW: %s" % (" " * len(k), " | ".join(name(i) for i in o[:3])))


if __name__ == "__main__":
    main()
