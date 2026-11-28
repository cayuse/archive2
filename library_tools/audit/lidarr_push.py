#!/usr/bin/env python3
"""Hand the artists behind broken songs to Lidarr, so it fetches their albums.

Each artist is added with every official studio album monitored (metadata profile "Standard") and the
"Archive" quality profile (good lossy or lossless, upgrades to lossless). Searches are queued so the
albums that hold broken songs go first, then everything else that is missing.

Artists already in Lidarr are left exactly as they are. Nothing in the archive is touched.

  lidarr_push.py --artists artists.tsv --broken broken.tsv [--apply]

artists.tsv: archive_artist_id, name, musicbrainz_id (tab separated, with a header)
broken.tsv:  musicbrainz_id, album title of a broken song (one line per broken song)
Without --apply it only prints what it would do. Needs LIDARR_URL and LIDARR_API_KEY in the
environment (~/.config/archive/lidarr.env).
"""
import argparse, csv, json, os, sys, time, urllib.parse, urllib.request
from collections import defaultdict

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "archive", "lib", "audio_audit"))
from textnorm import norm_album  # noqa: E402  (every script and language)

URL, KEY = os.environ["LIDARR_URL"].rstrip("/"), os.environ["LIDARR_API_KEY"]
QUALITY_PROFILE, METADATA_PROFILE, ROOT = "Archive", "Standard", "/datatank/lidarr"


def api(method, path, body=None, timeout=120):
    req = urllib.request.Request(f"{URL}/api/v1/{path}", method=method,
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers={"X-Api-Key": KEY, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)




def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--artists", required=True)
    ap.add_argument("--broken", required=True)
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()

    qp = {p["name"]: p["id"] for p in api("GET", "qualityprofile")}[QUALITY_PROFILE]
    mp = {p["name"]: p["id"] for p in api("GET", "metadataprofile")}[METADATA_PROFILE]
    have = {x["foreignArtistId"]: x for x in api("GET", "artist")}
    artists = list(csv.DictReader(open(a.artists, encoding="utf-8"), delimiter="\t"))
    broken_albums = defaultdict(set)
    for mbid, album in csv.reader(open(a.broken, encoding="utf-8"), delimiter="\t"):
        if norm_album(album):          # an album with no usable name matches nothing
            broken_albums[mbid].add(norm_album(album))

    added, kept, failed = [], [], []
    for r in artists:
        mbid = r["musicbrainz_id"]
        if mbid in have:
            kept.append((r["name"], have[mbid]["id"]))
            continue
        if not a.apply:
            added.append((r["name"], None)); continue
        try:
            found = api("GET", f"artist/lookup?term={urllib.parse.quote('lidarr:' + mbid)}")
            if not found:
                failed.append((r["name"], "not found in Lidarr's metadata")); continue
            x = found[0]
            # prolific artists (composers, jazz catalogues) only get the albums that hold broken songs
            # monitored; the rest are listed in Lidarr to pick by hand
            big = r.get("big") == "1"
            x.update(qualityProfileId=qp, metadataProfileId=mp, rootFolderPath=ROOT, monitored=True,
                     monitorNewItems="none" if big else "all",
                     addOptions={"monitor": "none" if big else "all", "searchForMissingAlbums": False})
            res = api("POST", "artist", x)
            have[mbid] = res
            added.append((r["name"], res["id"]))
            print(f"  added {r['name']}", file=sys.stderr)
        except Exception as ex:
            body = getattr(ex, "read", lambda: b"")().decode(errors="replace")[:200]
            failed.append((r["name"], f"{ex} {body}"))
        time.sleep(0.5)

    print(f"{len(added)} artists {'added' if a.apply else 'to add'}, {len(kept)} already in Lidarr (left as they are), "
          f"{len(failed)} failed")
    for n, why in failed:
        print(f"  failed: {n}: {why}")
    if not a.apply:
        return

    # Lidarr fills in each new artist's albums in the background; wait for that before matching
    print("waiting for Lidarr to load the albums ...", file=sys.stderr)
    ids = [i for _, i in added if i]
    for _ in range(120):
        if all(api("GET", f"album?artistId={i}") for i in ids[-5:]):
            break
        time.sleep(10)
    first, rest = [], 0
    for mbid, x in have.items():
        if x["id"] not in ids:
            continue
        albums = api("GET", f"album?artistId={x['id']}")
        want = broken_albums.get(mbid, set())
        hits = [al["id"] for al in albums if norm_album(al["title"]) in want]
        rest += sum(1 for al in albums if al.get("monitored") or al["id"] in hits)
        unmonitored = [al["id"] for al in albums if al["id"] in hits and not al.get("monitored")]
        if unmonitored:
            api("PUT", "album/monitor", {"albumIds": unmonitored, "monitored": True})
        first += hits
    if first:
        api("POST", "command", {"name": "AlbumSearch", "albumIds": first})
    api("POST", "command", {"name": "MissingAlbumSearch"})
    print(f"queued: {len(first)} albums that hold broken songs first, then all missing albums ({rest} monitored)")


if __name__ == "__main__":
    main()
