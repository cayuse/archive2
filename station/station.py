#!/usr/bin/env python3
"""Archive Station: the archive node's headless player. It plays whichever jukebox has been put
"on the speakers" in the archive, through OwnTone (AirPlay).

It is a jukebox *player*, like the browser AJB player, but with no browser. The archive is in charge:
every couple of seconds this daemon asks it which jukebox has the speakers (any party jukebox or
radio station, of any user allowed to play here) and whether that should be playing, paused or
stopped; it then asks for the next song, hands OwnTone a play link and reports now-playing back.
When a jukebox is switched over from a browser player it picks the song up where the browser was.
Transport, volume and speaker selection arrive from the archive's remote-control page the same way.

It also serves a small control page of its own on the LAN, which is just another remote: starting a
station there puts it on the speakers through the archive.

Runs on Linux, Python 3.9+, standard library only. Configuration is by environment variables:

  ARCHIVE_URL        base URL of the archive as seen from this host   (http://192.168.17.109:3000)
  NODE_TOKEN         the node's player token (archive: Settings -> Speakers). With it the daemon can
                     play any jukebox that is put on the speakers.
  ARCHIVE_EMAIL      optional login for the control page's search / station list (DJ or above, with
  ARCHIVE_PASSWORD   a local-playback grant). Without NODE_TOKEN the daemon polls as this account
                     and only plays this account's own jukeboxes.
  OWNTONE_URL        OwnTone JSON API                                 (http://127.0.0.1:3689)
  BIND_HOST          address the control page listens on - the LAN address, never 0.0.0.0 on a host
                     (in the container image it is 0.0.0.0 and the published port picks the address)
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
NODE_TOKEN = os.environ.get("NODE_TOKEN", "")
OWNTONE_URL = os.environ.get("OWNTONE_URL", "http://127.0.0.1:3689").rstrip("/")
BIND_HOST = os.environ.get("BIND_HOST", "127.0.0.1")
BIND_PORT = int(os.environ.get("BIND_PORT", "8337"))
STATE_FILE = Path(os.environ.get("STATE_FILE", "/data/station_state.json"))
LOOKAHEAD = 1          # songs lined up in OwnTone after the current one (gapless hand-over)
# The next song is only asked for this close to the end of the current one. Asking earlier would
# take it off the archive's queue a whole song ahead: a request made meanwhile would have to wait
# behind it, and every "up next" list would be one song out from what is heard.
LINE_UP_SECONDS = float(os.environ.get("LINE_UP_SECONDS", "20"))
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
    """The archive's API. Calls about the on-air jukebox go out with the node token (when there is
    one), so they work whoever owns it; search and the station list need the account login."""

    def __init__(self):
        self.token = None
        self.user = None
        self.lock = threading.Lock()

    def login(self):
        if not ARCHIVE_EMAIL:
            raise ValueError("no archive account is configured for this (set ARCHIVE_EMAIL / ARCHIVE_PASSWORD)")
        _, j = http("POST", ARCHIVE_URL + "/api/v1/auth/login", {"email": ARCHIVE_EMAIL, "password": ARCHIVE_PASSWORD})
        self.token, self.user = j["api_token"], j["user"]
        log("logged in to the archive as", self.user.get("name"), "(%s)" % self.user.get("role"))

    def call(self, method, path, body=None, as_user=False, timeout=20):
        if NODE_TOKEN and not as_user:
            return http(method, ARCHIVE_URL + path, body, {"X-Node-Token": NODE_TOKEN}, timeout)
        with self.lock:
            if not self.token:
                self.login()
        for attempt in (1, 2):
            try:
                return http(method, ARCHIVE_URL + path, body, {"Authorization": "Bearer " + self.token}, timeout)
            except HttpError as e:
                if e.status == 401 and attempt == 1:   # token expired: log in again once
                    with self.lock:
                        self.login()
                    continue
                raise

    def station(self, song_id=None, station_id=None, new=False):
        body = {k: v for k, v in {"song_id": song_id, "station_id": station_id, "new": new or None}.items() if v}
        return self.call("POST", "/api/v1/jukeboxes/station", body, as_user=True)[1]["jukebox"]

    def stations(self):
        return self.call("GET", "/api/v1/jukeboxes/stations", as_user=True)[1].get("stations", [])

    def sync(self, ack, state):
        """The poll: tell the archive how we are, learn which jukebox has the speakers."""
        return self.call("POST", "/api/v1/node_player/sync", {"ack": ack, "state": state}, timeout=10)[1]

    def on_air(self, jukebox_id, on, transport=None, fresh=False):
        body = {"on": on, "transport": transport, "fresh": fresh}
        return self.call("POST", "/api/v1/jukeboxes/%s/server_playback" % jukebox_id, body, as_user=True)[1]

    def transport(self, jukebox_id, command):
        return self.call("POST", "/api/v1/jukeboxes/%s/transport" % jukebox_id, {"command": command})[1]

    def feedback(self, jukebox_id, song_id, kind, position=None):
        body = {"song_id": song_id, "kind": kind}
        if position is not None:
            body["position"] = position
        return self.call("POST", "/api/v1/jukeboxes/%s/feedback" % jukebox_id, body)[1]

    def jukeboxes(self):
        return self.call("GET", "/api/v1/jukeboxes", as_user=True)[1].get("jukeboxes", [])

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
        return self.call("GET", "/api/v1/songs?" + qs, as_user=True)[1].get("songs", [])



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

    def pause(self):
        self.put("/api/player/pause")

    def seek(self, seconds):
        self.put("/api/player/seek?position_ms=%d" % max(0, int(seconds * 1000)))

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
    """Follows the archive: plays the jukebox that has the speakers, the way the archive says.
    One thread does all the work (tick); the control page only asks the archive to change things."""

    def __init__(self):
        self.archive = Archive()
        self.owntone = OwnTone()
        self.lock = threading.RLock()
        self.jukebox = None           # the on-air jukebox, as the archive last described it
        self.transport = "stop"       # what we last acted on: play / pause / stop
        self.loaded = False           # have we put anything into OwnTone for this jukebox?
        self.fresh = False            # just took this jukebox over: start with the archive's resume song
        self.seek = None              # (song id, seconds, when, moving) still to be sought to
        self.acked = 0                # last archive command carried out
        self.retuned = 0.0            # when we last dropped the lined-up song ourselves
        self.by_url = {}              # play link -> archive song dict, for the songs we handed to OwnTone
        self.current = None           # archive song dict now playing
        self.standing = None          # what the listener said about it: up / down / tired / never
        self.moved_on = set()         # song ids we skipped on purpose (so they are not "finished")
        self.position = 0.0
        self.length = 0.0             # length of the current song as OwnTone reports it
        self.sounding = False         # OwnTone is actually playing our song
        self.volume = 50
        self.error = None
        self.last_beat = 0.0
        self.last_station = None      # the station the control page last started (for its Resume button)
        self.saved_urls = set()
        self.session = {}             # jukebox id + songs handed to OwnTone, kept on disk across restarts
        self.last_tick = time.time()  # for /up: is the loop alive?
        self.tick_failed = False      # self.error came from a tick that raised
        self.load()

    # ---- persistence: the control page remembers which station it last started
    def load(self):
        try:
            s = json.loads(STATE_FILE.read_text())
            self.last_station = s.get("last_station") or ((s.get("jukebox") or {}).get("id") if (s.get("jukebox") or {}).get("station") else None)
            self.session = s.get("session") or {}
        except Exception:
            pass

    def save(self):
        try:
            STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
            session = {"jukebox_id": self.jukebox["id"], "by_url": self.by_url} if self.jukebox and self.loaded else {}
            STATE_FILE.write_text(json.dumps({"last_station": self.last_station, "session": session}))
        except Exception as e:
            log("could not save state:", e)

    # ---- commands from the control page: they go to the archive, and come back to us in tick()
    def start(self, song_id=None, jukebox_id=None, station_id=None, new=False):
        """Put a jukebox on the speakers: the one given, else the station last started here, else
        the account's first station. With song_id the station restarts from that song; with
        new=True a new station is made from it."""
        with self.lock:
            if jukebox_id:
                if not any(j["id"] == jukebox_id for j in self.archive.jukeboxes()):
                    raise ValueError("no such jukebox for this account")
                target = jukebox_id
            else:
                station_id = station_id or (None if new else self.last_station)
                try:
                    target = self.archive.station(song_id, station_id, new)["id"]
                except HttpError as e:
                    if e.status != 404 or not station_id:
                        raise
                    target = self.archive.station(song_id)["id"]      # that station was deleted
                self.last_station = target
                self.save()
            if song_id and self.jukebox and self.jukebox["id"] == target:
                self.release()                     # same station, restarted from a song: begin again
            self.archive.on_air(target, True, transport="play", fresh=bool(song_id))
            self.error = None
            log("START", target, "from song", song_id or "(resume)")
        self.nudge()

    def stop(self):
        with self.lock:
            if self.jukebox:
                self.archive.transport(self.jukebox["id"], "stop")
            log("STOP")
        self.nudge()

    def nudge(self):
        """Act on what we just asked the archive for without waiting for the next tick."""
        try:
            self.tick()
        except Exception as e:
            log("tick failed:", e)

    def skip(self, report=True):
        """Go to the next song. A skip the listener asked for is reported to the station (an early
        skip counts a little against the song); a skip that follows a thumbs down is not."""
        with self.lock:
            song = self.current
            if not song:
                return
            self.moved_on.add(song["id"])
            if report:
                self.event(song, "skip", self.position)
            # nothing is lined up until the song is nearly over, so get what follows now
            p, items = self.owntone.player(), self.owntone.queue()
            at = next((k for k, i in enumerate(items) if i["id"] == p.get("item_id")), None)
            if at is None or at == len(items) - 1:
                following = self.archive.next_song(self.jukebox["id"])
                if following:
                    self.by_url[following["play_url"]] = following
                    self.owntone.add(following["play_url"])
                    log("queued:", following.get("artist"), "-", following.get("title"))
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
            self.retuned = time.time()
            p = self.owntone.player()
            for item in self.owntone.queue():
                if item["id"] != p.get("item_id"):
                    http("DELETE", OWNTONE_URL + "/api/queue/items/%s" % item["id"], timeout=8)

    # ---- following the archive
    def report(self):
        """What the archive's remote-control page shows about this player."""
        out = {"error": self.error}
        try:
            out["outputs"] = [{"id": str(o["id"]), "name": o["name"], "type": o.get("type"), "selected": o["selected"]}
                              for o in self.owntone.outputs()]
            p = self.owntone.player()
            out["volume"], out["owntone_state"] = p.get("volume"), p.get("state")
        except Exception as e:
            out["error"] = "OwnTone is not answering: %s" % e
        return out

    def release(self):
        """Let go of the jukebox we were playing (the speakers went elsewhere, or nowhere)."""
        if self.jukebox:
            log("RELEASE", self.jukebox.get("name"))
        if self.loaded:
            try:
                self.owntone.stop()
                self.owntone.clear()
            except Exception as e:
                log("could not stop OwnTone:", e)
        self.jukebox, self.transport, self.loaded, self.fresh, self.seek = None, "stop", False, False, None
        self.saved_urls = set()
        self.save()
        self.by_url, self.current, self.standing, self.position, self.sounding = {}, None, None, 0.0, False

    def adopt(self, jukebox):
        # Restarted (a deploy, a crash) while this jukebox was playing? If everything in OwnTone's
        # queue is something we put there, carry on without a break in the music.
        saved, self.session = self.session, {}
        if saved.get("jukebox_id") == jukebox["id"] and jukebox.get("transport") != "stop":
            try:
                paths = [i["path"] for i in self.owntone.queue()]
            except Exception:
                paths = []
            known = saved.get("by_url") or {}
            if paths and all(p in known for p in paths):
                self.jukebox, self.transport, self.fresh, self.error = jukebox, None, False, None
                self.by_url, self.loaded = {p: known[p] for p in paths}, True
                log("ON AIR", jukebox.get("name"), "(carrying on after a restart)")
                return
        self.owntone.stop()
        self.owntone.clear()
        self.owntone.prepare()
        self.jukebox, self.transport, self.fresh, self.error = jukebox, None, True, None
        log("ON AIR", jukebox.get("name"), "(%s)" % jukebox.get("transport"))

    def command(self, c):
        """A one-shot command from the archive's remote."""
        cmd, value = c.get("cmd"), c.get("value")
        try:
            if cmd == "skip":
                self.skip(report=not (isinstance(value, dict) and value.get("report") is False))
            elif cmd == "volume":
                self.owntone.volume(value)
            elif cmd == "output":
                self.owntone.select(value["id"], value["selected"])
            elif cmd == "retune" and self.loaded and time.time() - self.retuned > 5:
                self.retune()
        except Exception as e:
            log("command %s failed:" % cmd, e)

    def beat(self, force=False):
        if not self.jukebox or (not force and time.time() - self.last_beat < HEARTBEAT):
            return
        self.last_beat = time.time()
        try:
            self.archive.heartbeat(self.jukebox["id"], self.current and self.current["id"], self.position,
                                   self.sounding, self.volume / 100.0)
        except Exception as e:
            log("heartbeat failed:", e)

    def tick(self):
        with self.lock:
            if self.tick_failed:           # the last tick blew up; if this one gets through, that is over
                self.error, self.tick_failed = None, False
            a = self.archive.sync(self.acked, self.report()) or {}
            target = a.get("jukebox")
            if (target or {}).get("id") != (self.jukebox or {}).get("id"):
                self.release()
                if target:
                    self.adopt(target)
            elif target:
                self.jukebox = target
            for c in a.get("commands") or []:
                if c.get("seq", 0) > self.acked:
                    self.acked = c["seq"]
                    if self.jukebox:
                        self.command(c)
            if not self.jukebox:
                return
            want = self.jukebox.get("transport") or "stop"
            changed, self.transport = want != self.transport, want

            if want == "stop":
                if self.loaded:
                    self.owntone.stop()
                    self.owntone.clear()
                    self.loaded = False
                self.by_url, self.current, self.standing, self.position, self.sounding = {}, None, None, 0.0, False
                self.fresh, self.seek = False, None
                self.beat(force=changed)
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
            was_sounding = self.sounding
            self.sounding = bool(self.current) and p.get("state") == "play"
            # report at once when a song starts or the sound starts / stops, not on the next heartbeat
            started = (bool(self.current) and before is not self.current) or was_sounding != self.sounding

            if want == "pause":
                if p.get("state") == "play":
                    self.owntone.pause()
                    self.sounding = False
                self.beat(force=changed or started)
                return

            # play
            resume = self.jukebox.get("resume")
            if self.fresh and not self.loaded and resume and resume.get("song"):
                song = resume["song"]             # taking over mid-song: same song, same place
                self.by_url[song["play_url"]] = song
                self.owntone.add(song["play_url"])
                self.loaded = True
                items = self.owntone.queue()
                if float(resume.get("position") or 0) > 3:
                    self.seek = (song["id"], float(resume["position"]), time.time(), bool(self.jukebox.get("live")))
                log("resuming:", song.get("artist"), "-", song.get("title"), "at %ds" % float(resume.get("position") or 0))
            self.fresh = False
            ahead = len(items) - (items.index(now) + 1 if now in items else 0)
            remaining = self.length - self.position if now and self.length else None
            if not now:
                want_ahead = 1                    # nothing playing: get the first song
            elif remaining is None or remaining <= LINE_UP_SECONDS:
                want_ahead = LOOKAHEAD            # near the end (or length unknown): line up what follows
            else:
                want_ahead = 0
            while ahead < want_ahead:
                song = self.archive.next_song(self.jukebox["id"])
                if not song:
                    self.error = "The archive has no next song for this jukebox (no playlists, or the seed song has not been analysed?)"
                    break
                self.error = None
                self.by_url[song["play_url"]] = song
                self.owntone.add(song["play_url"])
                self.loaded = True
                ahead += 1
                log("queued:", song.get("artist"), "-", song.get("title"))
            if len(self.by_url) > 8:       # forget songs long gone
                live = {i["path"] for i in self.owntone.queue()}
                self.by_url = {u: s for u, s in self.by_url.items() if u in live}
            if self.loaded and set(self.by_url) != self.saved_urls:
                self.saved_urls = set(self.by_url)
                self.save()
            if p.get("state") != "play" and (items or ahead):
                self.owntone.play()
            if self.seek:
                song_id, position, since, moving = self.seek
                if self.current and self.current["id"] != song_id:
                    self.seek = None
                elif self.sounding:
                    target_position = position + (time.time() - since if moving else 0)
                    if not self.length or target_position < self.length - 5:
                        self.owntone.seek(target_position)
                        self.position = target_position
                    self.seek = None
            self.beat(force=changed or started)

    def run(self):
        while True:
            self.last_tick = time.time()
            try:
                self.tick()
            except Exception as e:
                self.error, self.tick_failed = "%s: %s" % (type(e).__name__, e), True
                log("tick failed:", self.error)
                time.sleep(5)
            time.sleep(TICK)

    def state(self):
        with self.lock:
            out = {"playing": bool(self.jukebox) and self.transport == "play", "transport": self.transport,
                   "jukebox": self.jukebox, "current": self.current,
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
            if url.path == "/up":          # health check: the loop is alive (says nothing about the archive or OwnTone)
                alive = time.time() - STATION.last_tick < 60
                self.send(200 if alive else 503, {"ok": alive})
            elif url.path == "/":
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
                s.archive.request(s.jukebox["id"], b["song_id"])   # the archive tells us to retune if it re-aims
            elif path == "/api/settings":
                attrs = {k: b[k] for k in SETTINGS if k in b}
                s.jukebox = dict(s.jukebox, **s.archive.radio_settings(s.jukebox["id"], attrs))
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
    if not NODE_TOKEN and not (ARCHIVE_EMAIL and ARCHIVE_PASSWORD):
        raise SystemExit("set NODE_TOKEN (and, for the control page's search and stations, ARCHIVE_EMAIL and ARCHIVE_PASSWORD)")
    threading.Thread(target=STATION.run, daemon=True).start()
    log("control page on http://%s:%d  (archive %s, OwnTone %s)" % (BIND_HOST, BIND_PORT, ARCHIVE_URL, OWNTONE_URL))
    ThreadingHTTPServer((BIND_HOST, BIND_PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
