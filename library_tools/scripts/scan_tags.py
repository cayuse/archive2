#!/usr/bin/env python3
"""Read the embedded tags of every archive audio blob and write one JSON line per song.

Read-only on the audio files. Linux; needs python3 and mutagen (Debian: apt install python3-mutagen).

  scan_tags.py <songs.tsv> <out.jsonl> [workers]      bulk scan of the blob store
  scan_tags.py --file <path>                          one file; prints one JSON object (used by the Rails importer)

Storage root for the bulk scan: $ARCHIVE_STORAGE (default /datatank/archive/psql_storage).

songs.tsv columns (tab separated, no header): song_id, blob_key, checksum, filename
Rerunning with the same output file skips songs already written (resume).
"""
import json, os, re, sys, time
from multiprocessing import Pool
from pathlib import Path

from mutagen import File as MFile
from mutagen.flac import FLAC
from mutagen.id3 import ID3
from mutagen.mp3 import MP3, BitrateMode
from mutagen.mp4 import MP4

STORAGE = Path(os.environ.get("ARCHIVE_STORAGE", "/datatank/archive/psql_storage"))
UUID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", re.I)
MAXLEN = 2000

# canonical field -> names used by each tag format (Picard's mapping)
TXXX = {
    "musicbrainz_release_id": "MusicBrainz Album Id",
    "musicbrainz_release_group_id": "MusicBrainz Release Group Id",
    "musicbrainz_release_track_id": "MusicBrainz Release Track Id",
    "musicbrainz_work_id": "MusicBrainz Work Id",
    "musicbrainz_artist_ids": "MusicBrainz Artist Id",
    "musicbrainz_album_artist_ids": "MusicBrainz Album Artist Id",
    "acoustid_id": "Acoustid Id",
    "release_type": "MusicBrainz Album Type",
    "release_status": "MusicBrainz Album Status",
    "release_country": "MusicBrainz Album Release Country",
    "barcode": "BARCODE", "catalog_number": "CATALOGNUMBER", "asin": "ASIN", "script": "SCRIPT",
    "original_year": "originalyear", "acoustid_fingerprint": "Acoustid Fingerprint",
}
ID3_TEXT = {
    "title": "TIT2", "artist": "TPE1", "album": "TALB", "album_artist": "TPE2", "composer": "TCOM",
    "genre": "TCON", "track": "TRCK", "disc": "TPOS", "date_raw": "TDRC", "original_date_raw": "TDOR",
    "compilation": "TCMP", "label": "TPUB", "isrc": "TSRC", "artist_sort": "TSOP",
    "album_artist_sort": "TSO2", "album_sort": "TSOA", "media": "TMED", "language": "TLAN", "bpm": "TBPM",
}
MP4_TEXT = {
    "title": "\xa9nam", "artist": "\xa9ART", "album": "\xa9alb", "album_artist": "aART",
    "composer": "\xa9wrt", "genre": "\xa9gen", "date_raw": "\xa9day", "artist_sort": "soar",
    "album_artist_sort": "soaa", "album_sort": "soal", "bpm": "tmpo",
}
MP4_FREE = dict(TXXX, musicbrainz_recording_id="MusicBrainz Track Id", label="LABEL", isrc="ISRC",
                media="MEDIA", original_date_raw="originaldate", language="LANGUAGE")
VORBIS = {
    "title": ["title"], "artist": ["artist"], "album": ["album"], "album_artist": ["albumartist", "album artist"],
    "composer": ["composer"], "genre": ["genre"], "track": ["tracknumber"], "track_total": ["tracktotal", "totaltracks"],
    "disc": ["discnumber"], "disc_total": ["disctotal", "totaldiscs"], "date_raw": ["date"],
    "original_date_raw": ["originaldate"], "original_year": ["originalyear"], "compilation": ["compilation"],
    "label": ["label", "organization"], "catalog_number": ["catalognumber"], "barcode": ["barcode"],
    "isrc": ["isrc"], "asin": ["asin"], "media": ["media"], "language": ["language"], "script": ["script"],
    "bpm": ["bpm"], "artist_sort": ["artistsort"], "album_artist_sort": ["albumartistsort"],
    "album_sort": ["albumsort"], "release_type": ["releasetype"], "release_status": ["releasestatus"],
    "release_country": ["releasecountry"], "musicbrainz_recording_id": ["musicbrainz_trackid"],
    "musicbrainz_release_id": ["musicbrainz_albumid"], "musicbrainz_release_group_id": ["musicbrainz_releasegroupid"],
    "musicbrainz_release_track_id": ["musicbrainz_releasetrackid"], "musicbrainz_work_id": ["musicbrainz_workid"],
    "musicbrainz_artist_ids": ["musicbrainz_artistid"], "musicbrainz_album_artist_ids": ["musicbrainz_albumartistid"],
    "acoustid_id": ["acoustid_id"], "acoustid_fingerprint": ["acoustid_fingerprint"],
}
UUID_ONE = ["musicbrainz_recording_id", "musicbrainz_release_id", "musicbrainz_release_group_id",
            "musicbrainz_release_track_id", "musicbrainz_work_id", "acoustid_id"]
UUID_MANY = ["musicbrainz_artist_ids", "musicbrainz_album_artist_ids"]


def text(v):
    if isinstance(v, bytes):
        v = v.decode("utf-8", "replace")
    return str(v).replace("\x00", " ").strip()


def values(v):
    """Flatten a tag value into a list of clean strings."""
    if v is None:
        return []
    if hasattr(v, "text"):
        v = v.text
    if not isinstance(v, (list, tuple)):
        v = [v]
    out = []
    for x in v:
        if isinstance(x, tuple):
            x = "/".join(str(p) for p in x)
        s = text(x)
        if s:
            out.append(s)
    return out


def split_num(s):
    """'3/12' -> (3, 12); '3' -> (3, None)."""
    if not s:
        return None, None
    a, _, b = str(s).partition("/")
    num = lambda z: int(re.match(r"\d+", z.strip()).group()) if re.match(r"\d+", z.strip()) else None
    n, t = num(a), num(b)
    return (n if n else None), (t if t else None)


def from_id3(tags, got, raw):
    for key, frame in tags.items():
        fid = key[:4]
        if fid in ("APIC", "GEOB", "PRIV", "MCDI"):
            continue
        if fid == "UFID":
            if getattr(frame, "owner", "") == "http://musicbrainz.org":
                got["musicbrainz_recording_id"] = values(frame.data)
            continue
        vals = values(frame) if hasattr(frame, "text") else []
        if vals and "fingerprint" not in key.lower():
            raw[key] = [v[:MAXLEN] for v in vals]
    for field, fid in ID3_TEXT.items():
        if fid in tags:
            got[field] = values(tags[fid])
    for field, desc in TXXX.items():
        for key, frame in tags.items():
            if key[:5] == "TXXX:" and key[5:].lower() == desc.lower():
                got[field] = values(frame)
    got["has_cover_art"] = any(k.startswith("APIC") for k in tags.keys())
    got["has_lyrics"] = any(k.startswith("USLT") for k in tags.keys())


def from_mp4(tags, got, raw):
    for key, val in tags.items():
        if key == "covr":
            continue
        vals = values(val)
        if vals and "fingerprint" not in key.lower():
            raw[key] = [v[:MAXLEN] for v in vals]
    for field, atom in MP4_TEXT.items():
        if atom in tags:
            got[field] = values(tags[atom])
    if "trkn" in tags and tags["trkn"]:
        got["track"] = ["%s/%s" % tuple(tags["trkn"][0][:2])]
    if "disk" in tags and tags["disk"]:
        got["disc"] = ["%s/%s" % tuple(tags["disk"][0][:2])]
    if "cpil" in tags:
        got["compilation"] = ["1" if tags["cpil"] else "0"]
    lower = {k.lower(): k for k in tags.keys()}
    for field, name in MP4_FREE.items():
        k = lower.get(("----:com.apple.iTunes:" + name).lower())
        if k:
            got[field] = values(tags[k])
    got["has_cover_art"] = bool(tags.get("covr"))
    got["has_lyrics"] = "\xa9lyr" in tags


def from_vorbis(f, got, raw):
    tags = f.tags
    for key, val in tags.items():
        if key.lower() in ("metadata_block_picture", "coverart"):
            continue
        vals = values(val)
        if vals:
            raw[key.lower()] = [v[:MAXLEN] for v in vals]
    low = {k.lower(): values(v) for k, v in tags.items()}
    for field, names in VORBIS.items():
        for n in names:
            if low.get(n):
                got[field] = low[n]
                break
    raw.pop("acoustid_fingerprint", None)
    got["has_cover_art"] = bool(getattr(f, "pictures", None)) or "metadata_block_picture" in tags
    got["has_lyrics"] = "lyrics" in raw or "unsyncedlyrics" in raw


def scan(row):
    song_id, key, checksum, filename = row
    rec = {"song_id": song_id, "blob_key": key, "blob_checksum": checksum, "scan_error": None}
    return scan_path(STORAGE / key[0:2] / key[2:4] / key, rec)


def scan_path(path, rec):
    path = Path(path)
    try:
        if not path.exists():
            rec["scan_error"] = "file missing"
            return rec
        f = MFile(str(path))
        if f is None:
            rec["scan_error"] = "unrecognised audio format"
            return rec
        info = f.info
        kind = type(f).__name__
        rec["container"] = {"MP3": "mp3", "MP4": "mp4", "FLAC": "flac", "OggVorbis": "ogg", "OggOpus": "ogg",
                            "WAVE": "wav", "AAC": "aac"}.get(kind, kind.lower())
        rec["codec"] = getattr(info, "codec", None) or {"MP3": "mp3", "FLAC": "flac", "OggVorbis": "vorbis",
                                                         "OggOpus": "opus"}.get(kind, kind.lower())
        br = getattr(info, "bitrate", None)
        rec["bitrate"] = int(br) if br else None
        mode = getattr(info, "bitrate_mode", None)
        rec["bitrate_mode"] = {BitrateMode.CBR: "cbr", BitrateMode.VBR: "vbr", BitrateMode.ABR: "abr"}.get(mode)
        rec["sample_rate"] = getattr(info, "sample_rate", None)
        rec["channels"] = getattr(info, "channels", None)
        rec["bits_per_sample"] = getattr(info, "bits_per_sample", None) or None
        length = getattr(info, "length", None)
        rec["duration_seconds"] = round(float(length), 3) if length else None

        got, raw = {}, {}
        tags = f.tags
        if tags is None:
            rec["tag_format"] = None
        elif isinstance(tags, ID3) or kind in ("MP3", "WAVE", "AIFF", "AAC"):
            rec["tag_format"] = "ID3v2.%d" % tags.version[1] if hasattr(tags, "version") else "ID3"
            from_id3(tags, got, raw)
        elif isinstance(f, MP4):
            rec["tag_format"] = "MP4"
            from_mp4(tags, got, raw)
        else:
            rec["tag_format"] = "Vorbis"
            from_vorbis(f, got, raw)

        one = lambda k: (got.get(k) or [None])[0]
        for k in ("title", "artist", "album", "album_artist", "composer", "genre", "date_raw",
                  "original_date_raw", "artist_sort", "album_artist_sort", "album_sort", "label",
                  "catalog_number", "barcode", "isrc", "asin", "media", "release_type", "release_status",
                  "release_country", "language", "script"):
            v = got.get(k)
            rec[k] = "; ".join(v)[:MAXLEN] if v else None
        rec["track_number"], rec["track_total"] = split_num(one("track"))
        rec["disc_number"], rec["disc_total"] = split_num(one("disc"))
        if one("track_total"):
            rec["track_total"] = split_num(one("track_total"))[0] or rec["track_total"]
        if one("disc_total"):
            rec["disc_total"] = split_num(one("disc_total"))[0] or rec["disc_total"]
        if not rec["original_date_raw"] and one("original_year"):
            rec["original_date_raw"] = one("original_year")
        m = re.match(r"(\d{4})", rec["date_raw"] or "")
        rec["year"] = int(m.group(1)) if m and 1000 <= int(m.group(1)) <= 2100 else None
        comp = (one("compilation") or "").strip().lower()
        rec["compilation"] = comp in ("1", "true", "yes") if comp else None
        try:
            rec["bpm"] = round(float(one("bpm")), 2) if one("bpm") else None
        except ValueError:
            rec["bpm"] = None
        if not rec["bpm"] or not 20 <= rec["bpm"] <= 400:
            rec["bpm"] = None
        rec["acoustid_fingerprint"] = one("acoustid_fingerprint")
        for k in UUID_ONE:
            m = UUID.search(" ".join(got.get(k) or []))
            rec[k] = m.group().lower() if m else None
        for k in UUID_MANY:
            rec[k] = list(dict.fromkeys(u.lower() for u in UUID.findall(" ".join(got.get(k) or []))))
        rec["has_cover_art"] = bool(got.get("has_cover_art"))
        rec["has_lyrics"] = bool(got.get("has_lyrics"))
        rec["raw_tags"] = raw
    except Exception as e:  # one bad file must not stop the scan
        rec["scan_error"] = "%s: %s" % (type(e).__name__, str(e)[:300])
    return rec


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--file":
        sys.stdout.write(json.dumps(scan_path(sys.argv[2], {"scan_error": None}), ensure_ascii=False) + chr(10))
        return
    src, out = sys.argv[1], sys.argv[2]
    workers = int(sys.argv[3]) if len(sys.argv) > 3 else 6
    rows = [l.rstrip("\n").split("\t")[:4] for l in open(src, encoding="utf-8") if l.strip()]
    done = set()
    if Path(out).exists():
        for l in open(out, encoding="utf-8"):
            try:
                done.add(json.loads(l)["song_id"])
            except Exception:
                pass
    todo = [r for r in rows if r[0] not in done]
    print("total %d, already done %d, to scan %d" % (len(rows), len(done), len(todo)), flush=True)
    t0, n, errs = time.time(), 0, 0
    with open(out, "a", encoding="utf-8") as fh, Pool(workers) as pool:
        for rec in pool.imap_unordered(scan, todo, chunksize=50):
            fh.write(json.dumps(rec, ensure_ascii=False) + "\n")
            n += 1
            errs += 1 if rec.get("scan_error") else 0
            if n % 5000 == 0:
                print("%d/%d  errors %d  %.0f files/s" % (n, len(todo), errs, n / (time.time() - t0)), flush=True)
    print("DONE scanned %d errors %d in %.0fs" % (n, errs, time.time() - t0), flush=True)


if __name__ == "__main__":
    main()
