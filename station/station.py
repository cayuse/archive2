#!/usr/bin/env python3
"""Archive Station: a headless player that keeps an archive jukebox playing through OwnTone (AirPlay).

It is a jukebox *player*, like the browser AJB player, but with no browser: it asks the archive for
the next song, hands OwnTone a play link, reports now-playing back (so guests can request songs),
and repeats until told to stop. Controlled from a small web page that it serves on the LAN only.

Runs on Linux, Python 3.9+, standard library only. Configuration is by environment variables:

  ARCHIVE_URL        base URL of the archive as seen from this host   (http://192.168.17.109:3000)
  ARCHIVE_EMAIL      login of the account that owns the station (must be DJ, moderator or admin)
  ARCHIVE_PASSWORD   its password
  OWNTONE_URL        OwnTone JSON API                                 (http://127.0.0.1:3689)
  BIND_HOST          address the control page listens on - use the LAN address, never 0.0.0.0
  BIND_PORT          port of the control page                         (8337)
  STATE_FILE         where "was playing / which jukebox" is remembered across restarts
"""
import ipaddress
import json
import os
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ARCHIVE_URL = os.environ.get("ARCHIVE_URL", "http://192.168.17.109:3000").rstrip("/")
ARCHIVE_EMAIL = os.environ.get("ARCHIVE_EMAIL", "")
ARCHIVE_PASSWORD = os.environ.get("ARCHIVE_PASSWORD", "")
OWNTONE_URL = os.environ.get("OWNTONE_URL", "http://127.0.0.1:3689").rstrip("/")
BIND_HOST = os.environ.get("BIND_HOST", "127.0.0.1")
BIND_PORT = int(os.environ.get("BIND_PORT", "8337"))
STATE_FILE = Path(os.environ.get("STATE_FILE", "/data/station_state.json"))
LOOKAHEAD = 1          # songs kept queued in OwnTone after the current one (gapless hand-over)
TICK = 2.0             # seconds between looks at OwnTone
HEARTBEAT = 10.0       # seconds between now-playing reports to the archive (it treats 30 s as "live")
DIALS = ["danceability", "happiness", "aggression", "acousticness", "electronic", "instrumental"]
SETTINGS = ["genre", "reset_steer", "intensity", "variety", "learn"] + DIALS
MOVE_ON = ("down", "tired", "never")   # feedback that also skips the song
FINISHED_WITHIN = 10.0                 # seconds from the end that still count as "played to the end"


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


class HttpError(Exception):
    def __init__(self, status, body):
        super().__init__("HTTP %s: %s" % (status, body[:200]))
        self.status = status


def http(method, url, body=None, headers=None, timeout=20):
    data = None
    headers = dict(headers or {})
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read()
            status = r.status
    except urllib.error.HTTPError as e:
        raise HttpError(e.code, e.read().decode("utf-8", "replace"))
    if not raw:
        return status, None
    try:
        return status, json.loads(raw)
    except ValueError:
        return status, None


class Archive:
    """The archive's API, logged in as the station's owner."""

    def __init__(self):
        self.token = None
        self.user = None
        self.lock = threading.Lock()

    def login(self):
        _, j = http("POST", ARCHIVE_URL + "/api/v1/auth/login", {"email": ARCHIVE_EMAIL, "password": ARCHIVE_PASSWORD})
        self.token, self.user = j["api_token"], j["user"]
        log("logged in to the archive as", self.user.get("name"), "(%s)" % self.user.get("role"))

    def call(self, method, path, body=None):
        with self.lock:
            if not self.token:
                self.login()
        for attempt in (1, 2):
            try:
                return http(method, ARCHIVE_URL + path, body, {"Authorization": "Bearer " + self.token})
            except HttpError as e:
                if e.status == 401 and attempt == 1:   # token expired: log in again once
                    with self.lock:
                        self.login()
                    continue
                raise

    def station(self, song_id=None, station_id=None, new=False):
        body = {k: v for k, v in {"song_id": song_id, "station_id": station_id, "new": new or None}.items() if v}
        return self.call("POST", "/api/v1/jukeboxes/station", body)[1]["jukebox"]

    def stations(self):
        return self.call("GET", "/api/v1/jukeboxes/stations")[1].get("stations", [])

    def feedback(self, jukebox_id, song_id, kind, position=None):
        body = {"song_id": song_id, "kind": kind}
        if position is not None:
            body["position"] = position
        return self.call("POST", "/api/v1/jukeboxes/%s/feedback" % jukebox_id, body)[1]

    def jukeboxes(self):
        return self.call("GET", "/api/v1/jukeboxes")[1].get("jukeboxes", [])

    def next_song(self, jukebox_id):
        status, j = self.call("GET", "/api/v1/jukeboxes/%s/next_song" % jukebox_id)
        return j["song"] if status == 200 and j and j.get("success") else None

    def heartbeat(self, jukebox_id, song_id, position, playing, volume):
        body = {"position": position, "is_playing": playing, "volume": volume}
        if song_id:
            body["current_song_id"] = song_id
        self.call("POST", "/api/v1/jukeboxes/%s/playback_status" % jukebox_id, body)

    def queue(self, jukebox_id):
        return self.call("GET", "/api/v1/jukeboxes/%s/queue" % jukebox_id)[1]

    def request(self, jukebox_id, song_id):
        return self.call("POST", "/api/v1/jukeboxes/%s/queue" % jukebox_id, {"song_id": song_id, "source": "requested"})[1]

    def radio_settings(self, jukebox_id, attrs):
        return self.call("PATCH", "/api/v1/jukeboxes/%s/radio_settings" % jukebox_id, attrs)[1]["jukebox"]

    def search(self, q):
        qs = urllib.parse.urlencode({"search": q, "limit": 25, "sort_by": "title", "sort_order": "asc"})
        return self.call("GET", "/api/v1/songs?" + qs)[1].get("songs", [])



class OwnTone:
    def get(self, path):
        return http("GET", OWNTONE_URL + path, timeout=8)[1]

    def put(self, path, body=None):
        return http("PUT", OWNTONE_URL + path, body, timeout=8)[1]

    def player(self):
        return self.get("/api/player")

    def queue(self):
        return self.get("/api/queue").get("items", [])

    def outputs(self):
        return self.get("/api/outputs").get("outputs", [])

    def add(self, url):
        http("POST", OWNTONE_URL + "/api/queue/items/add?" + urllib.parse.urlencode({"uris": url}), timeout=15)

    def clear(self):
        self.put("/api/queue/clear")

    def play(self):
        self.put("/api/player/play")

    def stop(self):
        self.put("/api/player/stop")

    def next(self):
        self.put("/api/player/next")

    def volume(self, v):
        self.put("/api/player/volume?volume=%d" % max(0, min(100, int(v))))

    def select(self, output_id, selected):
        self.put("/api/outputs/%s" % output_id, {"selected": bool(selected)})

    def prepare(self):
        self.put("/api/player/consume?state=true")     # played songs leave the queue
        self.put("/api/player/repeat?state=off")
        self.put("/api/player/shuffle?state=false")


class Station:
    """Keeps OwnTone fed while 'playing' is on. One thread; everything else just flips flags."""

    def __init__(self):
        self.archive = Archive()
        self.owntone = OwnTone()
        self.lock = threading.RLock()
        self.playing = False
        self.jukebox = None           # dict from the archive (id, name, radio settings, ...)
        self.by_url = {}              # play link -> archive song dict, for the songs we handed to OwnTone
        self.current = None           # archive song dict now playing
        self.standing = None          # what the listener said about it: up / down / tired / never
        self.moved_on = set()         # song ids we skipped on purpose (so they are not "finished")
        self.position = 0.0
        self.length = 0.0             # length of the current song as OwnTone reports it
        self.volume = 50
        self.error = None
        self.last_beat = 0.0
        self.load()

    # ---- persistence: come back playing after a restart
    def load(self):
        try:
            s = json.loads(STATE_FILE.read_text())
            self.playing, self.jukebox = bool(s.get("playing")), s.get("jukebox")
        except Exception:
            pass

    def save(self):
        try:
            STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
            STATE_FILE.write_text(json.dumps({"playing": self.playing, "jukebox": self.jukebox}))
        except Exception as e:
            log("could not save state:", e)

    # ---- commands from the control page
    def start(self, song_id=None, jukebox_id=None, station_id=None, new=False):
        """Play a station: the one given, else the one we were on, else the account's first station.
        With song_id the station restarts from that song; with new=True a new station is made from it."""
        with self.lock:
            if jukebox_id:
                self.jukebox = next(({"id": j["id"], "name": j.get("name"), "station": False}
                                     for j in self.archive.jukeboxes() if j["id"] == jukebox_id), None)
                if not self.jukebox:
                    raise ValueError("no such jukebox for this account")
            else:
                if not station_id and not new and self.jukebox and self.jukebox.get("station"):
                    station_id = self.jukebox["id"]
                try:
                    self.jukebox = self.archive.station(song_id, station_id, new)
                except HttpError as e:
                    if e.status != 404 or not station_id:
                        raise
                    self.jukebox = self.archive.station(song_id)      # that station was deleted
            self.owntone.stop()
            self.owntone.clear()
            self.owntone.prepare()
            self.by_url, self.current, self.standing = {}, None, None
            self.playing, self.error = True, None
            self.save()
            log("START", self.jukebox.get("name"), "from song", song_id or "(resume)")

    def stop(self):
        with self.lock:
            self.playing = False
            self.save()
            try:
                self.owntone.stop()
                self.owntone.clear()
            finally:
                self.beat(force=True)
            self.by_url, self.current = {}, None
            log("STOP")

    def skip(self, report=True):
        """Go to the next song. A skip the listener asked for is reported to the station (an early
        skip counts a little against the song); a skip that follows a thumbs down is not."""
        with self.lock:
            song = self.current
            if song:
                self.moved_on.add(song["id"])
                if report:
                    self.event(song, "skip", self.position)
            self.owntone.next()

    def event(self, song, kind, position=None):
        try:
            self.archive.feedback(self.jukebox["id"], song["id"], kind, position)
        except Exception as e:
            log("could not report %s:" % kind, e)

    def feedback(self, song_id, kind):
        """What the listener says about a song: up, down, tired, never or clear."""
        with self.lock:
            out = self.archive.feedback(self.jukebox["id"], song_id, kind)
            if self.current and self.current["id"] == song_id:
                self.standing = out.get("standing")
                if kind in MOVE_ON:
                    self.retune()             # the station re-aimed: drop the song we had lined up
                    self.skip(report=False)
            return out

    def retune(self):
        """Settings or requests changed: drop the song we had lined up so the change is heard next."""
        with self.lock:
            p = self.owntone.player()
            for item in self.owntone.queue():
                if item["id"] != p.get("item_id"):
                    http("DELETE", OWNTONE_URL + "/api/queue/items/%s" % item["id"], timeout=8)

    # ---- the loop
    def beat(self, force=False):
        if not self.jukebox or (not force and time.time() - self.last_beat < HEARTBEAT):
            return
        self.last_beat = time.time()
        try:
            self.archive.heartbeat(self.jukebox["id"], self.current and self.current["id"], self.position,
                                   self.playing and self.current is not None, self.volume / 100.0)
        except Exception as e:
            log("heartbeat failed:", e)

    def tick(self):
        with self.lock:
            if not self.playing or not self.jukebox:
                return
            p = self.owntone.player()
            items = self.owntone.queue()
            self.volume = p.get("volume", self.volume)
            now = next((i for i in items if i["id"] == p.get("item_id")), None)
            before, before_position, before_length = self.current, self.position, self.length
            self.current = self.by_url.get(now["path"]) if now else None
            self.length = p.get("item_length_ms", 0) / 1000.0 if now else 0.0
            if before and (not self.current or self.current["id"] != before["id"]):
                self.standing = None
                length = before_length or float(before.get("duration") or 0)
                if before["id"] in self.moved_on:
                    self.moved_on.discard(before["id"])
                elif length and before_position >= length - FINISHED_WITHIN:
                    self.event(before, "finished")
            self.position = p.get("item_progress_ms", 0) / 1000.0 if now else 0.0
            ahead = len(items) - (items.index(now) + 1 if now else 0)
            want = LOOKAHEAD if now else LOOKAHEAD + 1
            while ahead < want:
                song = self.archive.next_song(self.jukebox["id"])
                if not song:
                    self.error = "The archive has no next song for this station (has the seed song been analysed?)"
                    break
                self.error = None
                self.by_url[song["play_url"]] = song
                self.owntone.add(song["play_url"])
                ahead += 1
                log("queued:", song.get("artist"), "-", song.get("title"))
            if len(self.by_url) > 50:      # forget songs long gone
                live = {i["path"] for i in items}
                self.by_url = {u: s for u, s in self.by_url.items() if u in live}
            if p.get("state") == "stop" and (items or ahead):
                self.owntone.play()
            self.beat()

    def run(self):
        while True:
            try:
                self.tick()
            except Exception as e:
                self.error = "%s: %s" % (type(e).__name__, e)
                log("tick failed:", self.error)
                time.sleep(5)
            time.sleep(TICK)

    def state(self):
        with self.lock:
            out = {"playing": self.playing, "jukebox": self.jukebox, "current": self.current,
                   "standing": self.standing, "position": self.position, "volume": self.volume, "error": self.error,
                   "archive_url": ARCHIVE_URL, "outputs": [], "upcoming": []}
        try:
            out["outputs"] = [{"id": o["id"], "name": o["name"], "type": o["type"], "selected": o["selected"]}
                              for o in self.owntone.outputs()]
            p = self.owntone.player()
            out["owntone_state"] = p.get("state")
        except Exception as e:
            out["error"] = out["error"] or "OwnTone is not answering: %s" % e
        if out["jukebox"]:
            try:
                q = self.archive.queue(out["jukebox"]["id"]) or {}
                out["upcoming"] = [{"title": i["song"]["title"], "artist": i["song"].get("artist"), "source": i.get("source")}
                                   for i in (q.get("queue") or q.get("items") or [])[:8]]
            except Exception:
                pass
        return out


STATION = Station()
PAGE = (Path(__file__).parent / "index.html").read_bytes()


def is_local(addr):
    try:
        ip = ipaddress.ip_address(addr.split("%")[0])
        return ip.is_private or ip.is_loopback
    except ValueError:
        return False


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, code, obj=None, raw=None, ctype="application/json"):
        body = raw if raw is not None else json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def guard(self):
        # LAN only, whatever BIND_HOST says; and reject requests relayed by a proxy from elsewhere.
        fwd = self.headers.get("X-Forwarded-For")
        ok = is_local(self.client_address[0]) and (not fwd or all(is_local(a.strip()) for a in fwd.split(",")))
        if not ok:
            self.send(403, {"error": "local network only"})
        return ok

    def do_GET(self):
        if not self.guard():
            return
        url = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(url.query)
        try:
            if url.path == "/":
                self.send(200, raw=PAGE, ctype="text/html; charset=utf-8")
            elif url.path == "/api/state":
                self.send(200, STATION.state())
            elif url.path == "/api/search":
                self.send(200, {"songs": STATION.archive.search(q.get("q", [""])[0])})
            elif url.path == "/api/jukeboxes":
                self.send(200, {"jukeboxes": STATION.archive.jukeboxes()})
            elif url.path == "/api/stations":
                self.send(200, {"stations": STATION.archive.stations()})
            else:
                self.send(404, {"error": "not found"})
        except Exception as e:
            self.send(500, {"error": "%s: %s" % (type(e).__name__, e)})

    def do_POST(self):
        if not self.guard():
            return
        n = int(self.headers.get("Content-Length") or 0)
        try:
            b = json.loads(self.rfile.read(n) or b"{}")
            path = urllib.parse.urlparse(self.path).path
            s = STATION
            if path == "/api/start":
                s.start(song_id=b.get("song_id"), jukebox_id=b.get("jukebox_id"),
                        station_id=b.get("station_id"), new=bool(b.get("new")))
            elif path == "/api/stop":
                s.stop()
            elif path == "/api/skip":
                s.skip()
            elif path == "/api/volume":
                s.owntone.volume(b["volume"])
            elif path == "/api/output":
                s.owntone.select(b["id"], b["selected"])
            elif path in ("/api/request", "/api/settings", "/api/feedback", "/api/rate") and not s.jukebox:
                raise ValueError("start a station first")
            elif path == "/api/request":
                s.archive.request(s.jukebox["id"], b["song_id"])
                s.retune()
            elif path == "/api/settings":
                attrs = {k: b[k] for k in SETTINGS if k in b}
                s.jukebox = dict(s.jukebox, **s.archive.radio_settings(s.jukebox["id"], attrs))
                s.save()
                s.retune()
            elif path in ("/api/feedback", "/api/rate"):
                if not b.get("song_id"):
                    raise ValueError("nothing is playing")
                kind = b.get("kind") or {1: "up", -1: "down", 0: "clear"}[int(b.get("value", 0))]   # rate: old page
                s.feedback(b["song_id"], kind)
            else:
                return self.send(404, {"error": "not found"})
            self.send(200, s.state())
        except Exception as e:
            log("command failed:", self.path, e)
            self.send(500, {"error": "%s: %s" % (type(e).__name__, e)})


def main():
    if not ARCHIVE_EMAIL or not ARCHIVE_PASSWORD:
        raise SystemExit("set ARCHIVE_EMAIL and ARCHIVE_PASSWORD")
    threading.Thread(target=STATION.run, daemon=True).start()
    log("control page on http://%s:%d  (archive %s, OwnTone %s)" % (BIND_HOST, BIND_PORT, ARCHIVE_URL, OWNTONE_URL))
    ThreadingHTTPServer((BIND_HOST, BIND_PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
