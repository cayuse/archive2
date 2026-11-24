#!/usr/bin/env python3
"""A stand-in for OwnTone's JSON API, for testing station.py without touching real speakers.

Implements only what station.py calls. "Plays" each queued item for SONG_SECONDS, then consumes it.
  python3 mock_owntone.py [port]
"""
import json
import os
import sys
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SONG_SECONDS = float(os.environ.get("SONG_SECONDS", "4"))
L = threading.Lock()
S = {"state": "stop", "queue": [], "next_id": 1, "started": 0.0, "volume": 50,
     "outputs": [{"id": "1", "name": "Mock Speaker", "type": "AirPlay 2", "selected": True}], "log": []}


def advance():
    while True:
        time.sleep(0.2)
        with L:
            if S["state"] == "play" and S["queue"] and time.time() - S["started"] >= SONG_SECONDS:
                done = S["queue"].pop(0)
                S["log"].append(done["path"])
                S["started"] = time.time()
                if not S["queue"]:
                    S["state"] = "stop"


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def out(self, obj=None, code=200):
        body = json.dumps(obj).encode() if obj is not None else b""
        self.send_response(code if body else 204)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n) or b"{}") if n else {}

    def do_GET(self):
        p = urllib.parse.urlparse(self.path).path
        with L:
            if p == "/api/player":
                cur = S["queue"][0] if S["queue"] and S["state"] != "stop" else None
                self.out({"state": S["state"], "volume": S["volume"], "item_id": cur["id"] if cur else 0,
                          "item_progress_ms": int((time.time() - S["started"]) * 1000) if cur else 0})
            elif p == "/api/queue":
                self.out({"count": len(S["queue"]), "items": S["queue"]})
            elif p == "/api/outputs":
                self.out({"outputs": S["outputs"]})
            elif p == "/mock/log":
                self.out({"played": S["log"]})
            else:
                self.out({"error": "?"}, 404)

    def do_POST(self):
        u = urllib.parse.urlparse(self.path)
        if u.path == "/api/queue/items/add":
            with L:
                for uri in urllib.parse.parse_qs(u.query)["uris"][0].split(","):
                    S["queue"].append({"id": S["next_id"], "path": uri})
                    S["next_id"] += 1
            self.out({"count": 1})
        else:
            self.out({"error": "?"}, 404)

    def do_PUT(self):
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        b = self.body()
        with L:
            if u.path == "/api/player/play":
                if S["queue"] and S["state"] != "play":
                    S["state"], S["started"] = "play", time.time()
            elif u.path == "/api/player/stop":
                S["state"] = "stop"
            elif u.path == "/api/player/next":
                if S["queue"]:
                    S["queue"].pop(0)
                    S["started"] = time.time()
                    if not S["queue"]:
                        S["state"] = "stop"
            elif u.path == "/api/player/volume":
                S["volume"] = int(q["volume"][0])
            elif u.path == "/api/queue/clear":
                S["queue"] = []
            elif u.path.startswith("/api/outputs/"):
                for o in S["outputs"]:
                    if o["id"] == u.path.rsplit("/", 1)[1]:
                        o["selected"] = b.get("selected", o["selected"])
        self.out()

    def do_DELETE(self):
        p = urllib.parse.urlparse(self.path).path
        with L:
            S["queue"] = [i for i in S["queue"] if str(i["id"]) != p.rsplit("/", 1)[1]]
        self.out()


if __name__ == "__main__":
    threading.Thread(target=advance, daemon=True).start()
    ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1]) if len(sys.argv) > 1 else 3690), H).serve_forever()
