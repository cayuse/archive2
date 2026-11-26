#!/usr/bin/env python3
"""Rewrite one audio file's tags in a single standard layout.

  write_tags.py <audio file> <tags.json>

tags.json holds the values to write, keyed like scan_tags.py's output (the song_file_tags columns).
A key that is missing or null is not written. The file's old text tags are REPLACED, not merged:
whatever the ripper or an earlier tagger left behind (comments, rip logs, private frames, a second
tag block in another format) is dropped. Kept from the old tags: embedded pictures, lyrics and
ReplayGain values.

The layout is the one MusicBrainz Picard writes, so any player or tagger reads it:
  mp3   ID3v2.4, UTF-8; ID3v1 and APEv2 blocks removed
  flac  Vorbis comments (upper-case names); pictures kept
  ogg / opus  Vorbis comments
  m4a / mp4   iTunes atoms, with ----:com.apple.iTunes freeform atoms for the rest
Other formats (wav, aac) are left untouched: exit status 3.

Only tag blocks are rewritten. The audio stream is not touched; the Rails side verifies that by
comparing the decoded audio before and after.
"""
import json, sys

from mutagen import File as MFile
from mutagen.apev2 import APEv2, APENoHeaderError
from mutagen.flac import FLAC
from mutagen.id3 import ID3, ID3NoHeaderError, TXXX, UFID, Frames
from mutagen.mp3 import MP3
from mutagen.mp4 import MP4, MP4FreeForm
from mutagen.oggopus import OggOpus
from mutagen.oggvorbis import OggVorbis

# field -> (ID3 frame or TXXX description, Vorbis name, MP4 atom or freeform name)
TEXT = {
    "title": ("TIT2", "TITLE", "\xa9nam"),
    "artist": ("TPE1", "ARTIST", "\xa9ART"),
    "album": ("TALB", "ALBUM", "\xa9alb"),
    "album_artist": ("TPE2", "ALBUMARTIST", "aART"),
    "composer": ("TCOM", "COMPOSER", "\xa9wrt"),
    "genre": ("TCON", "GENRE", "\xa9gen"),
    "date_raw": ("TDRC", "DATE", "\xa9day"),
    "original_date_raw": ("TDOR", "ORIGINALDATE", "----:originaldate"),
    "artist_sort": ("TSOP", "ARTISTSORT", "soar"),
    "album_artist_sort": ("TSO2", "ALBUMARTISTSORT", "soaa"),
    "album_sort": ("TSOA", "ALBUMSORT", "soal"),
    "label": ("TPUB", "LABEL", "----:LABEL"),
    "isrc": ("TSRC", "ISRC", "----:ISRC"),
    "media": ("TMED", "MEDIA", "----:MEDIA"),
    "language": ("TLAN", "LANGUAGE", "----:LANGUAGE"),
    "catalog_number": ("TXXX:CATALOGNUMBER", "CATALOGNUMBER", "----:CATALOGNUMBER"),
    "barcode": ("TXXX:BARCODE", "BARCODE", "----:BARCODE"),
    "asin": ("TXXX:ASIN", "ASIN", "----:ASIN"),
    "script": ("TXXX:SCRIPT", "SCRIPT", "----:SCRIPT"),
    "release_type": ("TXXX:MusicBrainz Album Type", "RELEASETYPE", "----:MusicBrainz Album Type"),
    "release_status": ("TXXX:MusicBrainz Album Status", "RELEASESTATUS", "----:MusicBrainz Album Status"),
    "release_country": ("TXXX:MusicBrainz Album Release Country", "RELEASECOUNTRY", "----:MusicBrainz Album Release Country"),
    "musicbrainz_release_id": ("TXXX:MusicBrainz Album Id", "MUSICBRAINZ_ALBUMID", "----:MusicBrainz Album Id"),
    "musicbrainz_release_group_id": ("TXXX:MusicBrainz Release Group Id", "MUSICBRAINZ_RELEASEGROUPID", "----:MusicBrainz Release Group Id"),
    "musicbrainz_release_track_id": ("TXXX:MusicBrainz Release Track Id", "MUSICBRAINZ_RELEASETRACKID", "----:MusicBrainz Release Track Id"),
    "musicbrainz_work_id": ("TXXX:MusicBrainz Work Id", "MUSICBRAINZ_WORKID", "----:MusicBrainz Work Id"),
    "musicbrainz_artist_ids": ("TXXX:MusicBrainz Artist Id", "MUSICBRAINZ_ARTISTID", "----:MusicBrainz Artist Id"),
    "musicbrainz_album_artist_ids": ("TXXX:MusicBrainz Album Artist Id", "MUSICBRAINZ_ALBUMARTISTID", "----:MusicBrainz Album Artist Id"),
    "acoustid_id": ("TXXX:Acoustid Id", "ACOUSTID_ID", "----:Acoustid Id"),
    "musicbrainz_recording_id": (None, "MUSICBRAINZ_TRACKID", "----:MusicBrainz Track Id"),   # ID3: a UFID frame
}
FREEFORM = "----:com.apple.iTunes:"
SPLIT = {"release_type"}      # stored joined with "; ", written as separate values
KEEP_ID3 = ("APIC", "USLT", "SYLT")
KEEP_VORBIS = ("replaygain_", "lyrics", "unsyncedlyrics", "metadata_block_picture", "coverart")


def listed(tags, field):
    v = tags.get(field)
    if v is None or v == "" or v == []:
        return []
    if isinstance(v, list):
        return [str(x) for x in v if str(x).strip()]
    if field in SPLIT:
        return [p.strip() for p in str(v).split(";") if p.strip()]
    return [str(v).strip()]


def pair(tags, number, total):
    n, t = tags.get(number), tags.get(total)
    return (int(n) if n else 0, int(t) if t else 0)


def write_id3(path, tags):
    audio = MP3(path)
    old = audio.tags if audio.tags is not None else ID3()
    new = ID3()
    for key, frame in old.items():
        if key[:4] in KEEP_ID3 or (key[:5] == "TXXX:" and key[5:].lower().startswith("replaygain_")):
            new.add(frame)
    for field, (frame, _, _) in TEXT.items():
        vals = listed(tags, field)
        if not vals or frame is None:
            continue
        if frame.startswith("TXXX:"):
            new.add(TXXX(encoding=3, desc=frame[5:], text=vals))
        else:
            new.add(Frames[frame](encoding=3, text=vals))
    if tags.get("musicbrainz_recording_id"):
        new.add(UFID(owner="http://musicbrainz.org", data=str(tags["musicbrainz_recording_id"]).encode("ascii")))
    for frame, (n, t) in (("TRCK", pair(tags, "track_number", "track_total")), ("TPOS", pair(tags, "disc_number", "disc_total"))):
        if n:
            new.add(Frames[frame](encoding=3, text=["%d/%d" % (n, t) if t else str(n)]))
    if tags.get("compilation"):
        new.add(Frames["TCMP"](encoding=3, text=["1"]))
    if tags.get("original_date_raw"):
        new.add(TXXX(encoding=3, desc="originalyear", text=[str(tags["original_date_raw"])[:4]]))
    audio.tags = new
    audio.save(v1=0, v2_version=4)          # v1=0 removes an ID3v1 block
    try:
        APEv2(path).delete()                # a second, older tag block some rippers add
    except APENoHeaderError:
        pass


def write_vorbis(audio, tags):
    kept = [(k, v) for k, v in audio.tags if k.lower().startswith(KEEP_VORBIS)] if audio.tags is not None else []
    if audio.tags is None:
        audio.add_tags()
    audio.tags.clear()
    for k, v in kept:
        audio.tags.append((k, v))
    for field, (_, name, _) in TEXT.items():
        vals = listed(tags, field)
        if vals:
            audio.tags[name] = vals
    for num, tot, total_name in (("TRACKNUMBER", "track_total", "TRACKTOTAL"), ("DISCNUMBER", "disc_total", "DISCTOTAL")):
        n = tags.get("track_number" if num == "TRACKNUMBER" else "disc_number")
        if n:
            audio.tags[num] = [str(int(n))]
            if tags.get(tot):
                audio.tags[total_name] = [str(int(tags[tot]))]
    if tags.get("compilation"):
        audio.tags["COMPILATION"] = ["1"]
    if tags.get("original_date_raw"):
        audio.tags["ORIGINALYEAR"] = [str(tags["original_date_raw"])[:4]]
    audio.save()


def write_mp4(path, tags):
    audio = MP4(path)
    old = audio.tags or {}
    kept = {k: v for k, v in old.items() if k in ("covr", "\xa9lyr") or k.lower().startswith(FREEFORM.lower() + "replaygain_")}
    if audio.tags is None:
        audio.add_tags()
    audio.tags.clear()
    audio.tags.update(kept)
    for field, (_, _, atom) in TEXT.items():
        vals = listed(tags, field)
        if not vals:
            continue
        if atom.startswith("----:"):
            audio.tags[FREEFORM + atom[5:]] = [MP4FreeForm(v.encode("utf-8")) for v in vals]
        else:
            audio.tags[atom] = vals
    trk, dsk = pair(tags, "track_number", "track_total"), pair(tags, "disc_number", "disc_total")
    if trk[0]:
        audio.tags["trkn"] = [trk]
    if dsk[0]:
        audio.tags["disk"] = [dsk]
    if tags.get("compilation"):
        audio.tags["cpil"] = True
    audio.save()


def main():
    path, tags = sys.argv[1], json.load(open(sys.argv[2], encoding="utf-8"))
    audio = MFile(path)
    if isinstance(audio, MP3):
        write_id3(path, tags)
    elif isinstance(audio, (FLAC, OggVorbis, OggOpus)):
        if isinstance(audio, FLAC):
            try:
                ID3(path).delete(path)       # an ID3 block glued onto a FLAC confuses players
                audio = FLAC(path)
            except ID3NoHeaderError:
                pass
        write_vorbis(audio, tags)
    elif isinstance(audio, MP4):
        write_mp4(path, tags)
    else:
        sys.stderr.write("tags are not rewritten for this format\n")
        sys.exit(3)


if __name__ == "__main__":
    main()
