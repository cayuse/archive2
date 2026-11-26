"""Driver for server_player_e2e.sh: plays the part of the browser pages and checks what the daemon did."""
import json
import os
import sys
import time
import urllib.request

ARCHIVE, MOCK = "http://127.0.0.1:3909", "http://127.0.0.1:3691"
PARTY, OTHER, SONG = os.environ["PARTY"], os.environ.get("OTHER"), os.environ.get("SONG")
failed = []


def call(method, url, body=None, token=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        return e.code, {}


def check(what, ok, detail=""):
    print("  %s %s %s" % ("ok  " if ok else "FAIL", what, detail))
    if not ok:
        failed.append(what)


def wait(what, test, seconds=12):
    end = time.time() + seconds
    while time.time() < end:
        value = test()
        if value:
            return check(what, True, "" if value is True else str(value))
        time.sleep(0.5)
    check(what, False)


TOKEN = call("POST", ARCHIVE + "/api/v1/auth/login", {"email": "station-test@example.invalid", "password": os.environ["STAGING_TEST_PASSWORD"]})[1]["api_token"]
api = lambda method, path, body=None: call(method, ARCHIVE + "/api/v1" + path, body, TOKEN)
status = lambda jb: api("GET", "/jukeboxes/%s/status" % jb)[1]["jukebox"]
owntone = lambda: call("GET", MOCK + "/api/player")[1]
mock_queue = lambda: call("GET", MOCK + "/api/queue")[1]["items"]

mock = lambda: call("GET", MOCK + "/mock/log")[1]
MARK = "/tmp/server_player_e2e_mark.json"
if sys.argv[1:] == ["start-playing"]:
    api("POST", "/jukeboxes/%s/server_playback" % PARTY, {"on": True, "transport": "play", "fresh": True})
    wait("playing, with a song lined up", lambda: owntone()["state"] == "play" and len(mock_queue()) == 2 and status(PARTY)["is_playing"], 15)
    json.dump({"clears": mock()["clears"], "queue": [i["path"] for i in mock_queue()]}, open(MARK, "w"))
    sys.exit(1 if failed else 0)
if sys.argv[1:] == ["still-playing"]:
    mark = json.load(open(MARK))
    check("OwnTone was never stopped or cleared", owntone()["state"] == "play" and mock()["clears"] == mark["clears"])
    check("same songs in its queue", [i["path"] for i in mock_queue()] == mark["queue"])
    wait("the daemon knows the song again and reports it", lambda: status(PARTY)["is_playing"] and status(PARTY)["server"]["online"] and status(PARTY)["current_song"]["title"])
    api("POST", "/jukeboxes/%s/transport" % PARTY, {"command": "skip"})
    wait("and still obeys the remote (skip)", lambda: mock_queue() and mock_queue()[0]["path"] == mark["queue"][1], 10)
    api("POST", "/jukeboxes/%s/server_playback" % PARTY, {"on": False})
    wait("released", lambda: owntone()["state"] == "stop")
    sys.exit(1 if failed else 0)

print("== idle: the daemon is polling, nothing on the speakers")
wait("daemon online", lambda: api("POST", "/jukeboxes/%s/server_playback" % OTHER, {"on": True})[0] == 200 and status(OTHER)["server"]["online"])
api("POST", "/jukeboxes/%s/server_playback" % OTHER, {"on": False})
check("OwnTone untouched", owntone()["state"] == "stop" and not mock_queue())

print("== a browser is playing the party jukebox, 40 s into a song; the owner flips the switch")
api("POST", "/jukeboxes/%s/playback_status" % PARTY, {"current_song_id": SONG, "position": 40, "is_playing": True})
time.sleep(1)
check("switch on", api("POST", "/jukeboxes/%s/server_playback" % PARTY, {"on": True})[0] == 200)
s = status(PARTY)
check("transport carried over as play", s["server"]["transport"] == "play", s["server"]["transport"])
code, late = api("POST", "/jukeboxes/%s/playback_status" % PARTY, {"current_song_id": SONG, "position": 5, "is_playing": True})
check("the browser's next heartbeat is told to yield", late.get("server_playback") is True)
wait("daemon plays the same song", lambda: owntone()["state"] == "play" and status(PARTY)["is_playing"] and status(PARTY)["current_song"]["id"] == SONG)
wait("...from where the browser was", lambda: 40 <= owntone()["item_progress_ms"] / 1000 <= 60 and "%.0fs" % (owntone()["item_progress_ms"] / 1000))
wait("a second song is lined up", lambda: len(mock_queue()) == 2)

print("== remote: pause, play, volume, speaker, skip")
api("POST", "/jukeboxes/%s/transport" % PARTY, {"command": "pause"})
wait("paused", lambda: owntone()["state"] == "pause")
held = owntone()["item_progress_ms"]
check("archive shows paused at once", status(PARTY)["is_playing"] is False)
api("POST", "/jukeboxes/%s/transport" % PARTY, {"command": "play"})
wait("playing again in place", lambda: owntone()["state"] == "play" and owntone()["item_progress_ms"] >= held and status(PARTY)["is_playing"])
api("POST", "/node_player/command", {"cmd": "volume", "value": 23})
wait("volume set", lambda: owntone()["volume"] == 23 and status(PARTY)["server"]["volume"] == 23)
api("POST", "/node_player/command", {"cmd": "output", "id": "1", "selected": False})
wait("speaker switched off", lambda: status(PARTY)["server"]["outputs"] and status(PARTY)["server"]["outputs"][0]["selected"] is False)
api("POST", "/node_player/command", {"cmd": "output", "id": "1", "selected": True})
api("POST", "/jukeboxes/%s/transport" % PARTY, {"command": "skip"})
wait("skipped to another song", lambda: (status(PARTY)["current_song"] or {}).get("id") not in (None, SONG) and status(PARTY)["current_song"]["title"], 15)

print("== an admin-code guest pauses from their phone")
code, _ = call("POST", ARCHIVE + "/api/v1/guest/%s/player_command?password=e2eadmin" % PARTY, {"command": "pause"})
check("guest command accepted", code == 200, str(code))
wait("paused", lambda: owntone()["state"] == "pause")

print("== another jukebox takes the speakers")
api("POST", "/jukeboxes/%s/server_playback" % OTHER, {"on": True, "transport": "play"})
check("party jukebox is back in browser mode", status(PARTY)["server_playback"] is False and status(PARTY)["current_song"] is not None)
wait("daemon plays the other jukebox", lambda: status(OTHER)["is_playing"] and owntone()["state"] == "play" and status(OTHER)["current_song"]["title"], 15)

print("== stop, then play again starts a new song")
before = status(OTHER)["current_song"]["id"]
api("POST", "/jukeboxes/%s/transport" % OTHER, {"command": "stop"})
wait("stopped and cleared", lambda: owntone()["state"] == "stop" and not mock_queue() and status(OTHER)["current_song"] is None)
api("POST", "/jukeboxes/%s/transport" % OTHER, {"command": "play"})
wait("playing a new song", lambda: status(OTHER)["is_playing"] and status(OTHER)["current_song"]["id"] != before, 15)

print("== hand back to the browser")
time.sleep(3)
api("POST", "/jukeboxes/%s/server_playback" % OTHER, {"on": False})
s = status(OTHER)
check("song and place kept for the browser, not playing", s["current_song"] is not None and s["is_playing"] is False and float(s["current_position"]) > 0, "%.0fs" % float(s["current_position"]))
wait("daemon let go of the speakers", lambda: owntone()["state"] == "stop" and not mock_queue())
code, _ = api("POST", "/jukeboxes/%s/playback_status" % OTHER, {"current_song_id": s["current_song"]["id"], "position": 7, "is_playing": True})
check("the browser player's reports count again", float(status(OTHER)["current_position"]) == 7)

print("FAILED: %s" % ", ".join(failed) if failed else "ALL OK")
sys.exit(1 if failed else 0)
