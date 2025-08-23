#!/usr/bin/env python3
import os, sys, json, time, socket, subprocess, threading, queue, logging, signal
from typing import Optional, Dict, Any
import redis
import requests

# ------------------- config -------------------
REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
REDIS_DB   = int(os.getenv("REDIS_DB", "1"))
API_BASE   = os.getenv("JUKEBOX_API_URL", "http://localhost:3001/api")
VOLUME     = int(os.getenv("JUKEBOX_VOLUME", "80"))          # 0..100
IPC_PATH   = os.getenv("JUKEBOX_MPV_SOCKET", "/tmp/jukebox_mpv.sock")
CACHE_SECS = int(os.getenv("JUKEBOX_CACHE_SECS", "20"))      # mpv read-ahead cache (~20s)
STATUS_KEY = "jukebox:player_status"
CMD_LIST   = "jukebox:commands"
CUR_SONG   = "jukebox:current_song"
DESIRED    = "jukebox:desired_state"  # playing|paused|stopped

logging.basicConfig(level=logging.INFO,
                    format="%(asctime)s - %(levelname)s - %(message)s")
log = logging.getLogger("jukebox")

# ------------------- mpv JSON IPC -------------------
class MPV:
    """
    Minimal mpv JSON IPC helper.
    We spawn mpv with --input-ipc-server=IPC_PATH and do request/response JSON over UNIX socket.
    No callback/event handling; the run-loop polls properties it needs.
    """
    def __init__(self, ipc_path: str):
        self.ipc_path = ipc_path
        self.proc: Optional[subprocess.Popen] = None
        self.sock: Optional[socket.socket] = None
        self.reader_thread: Optional[threading.Thread] = None
        self._req_id = 0
        self._lock = threading.Lock()
        self._resp_cv = threading.Condition(self._lock)
        self._responses: Dict[int, Any] = {}
        self._stop_reader = threading.Event()

    def start(self):
        # cleanup stale socket file
        try:
            if os.path.exists(self.ipc_path):
                os.unlink(self.ipc_path)
        except Exception:
            pass

        args = [
            "mpv",
            "--no-video",
            "--idle=yes",                 # stay running when no file loaded
            "--force-window=no",
            f"--input-ipc-server={self.ipc_path}",
            f"--volume={VOLUME}",
            "--audio-client-name=jukebox",
            "--ytdl=no",
            "--term-status-msg=",
            "--cache=yes",
            f"--cache-secs={CACHE_SECS}",
        ]
        try:
            self.proc = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except FileNotFoundError:
            raise RuntimeError("mpv executable not found in PATH")
        except Exception as e:
            raise RuntimeError(f"Failed to start mpv: {e}")

        # wait for socket
        for _ in range(50):  # ~5s
            try:
                self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                self.sock.connect(self.ipc_path)
                # Blocking send simplifies correctness; reader thread handles recv.
                self.sock.setblocking(True)
                break
            except Exception:
                time.sleep(0.1)
        if not self.sock:
            raise RuntimeError("Failed to connect to mpv IPC socket")

        # start reader thread
        self.reader_thread = threading.Thread(target=self._reader, daemon=True)
        self.reader_thread.start()

        # Observe (optional; harmless even though we poll)
        for prop in ("time-pos", "duration", "pause", "volume", "idle-active", "path"):
            self.observe_property(prop)

    def _reader(self):
        buf = b""
        while not self._stop_reader.is_set():
            try:
                if self.proc and self.proc.poll() is not None:
                    # mpv exited; wake any waiters
                    with self._resp_cv:
                        self._stop_reader.set()
                        self._resp_cv.notify_all()
                    return
                if not self.sock:
                    time.sleep(0.05); continue
                try:
                    chunk = self.sock.recv(4096)
                    if not chunk:
                        time.sleep(0.05); continue
                    buf += chunk
                    while b"\n" in buf:
                        line, buf = buf.split(b"\n", 1)
                        line = line.strip()
                        if not line:
                            continue
                        try:
                            obj = json.loads(line.decode("utf-8", "replace"))
                            # Route responses; ignore unsolicited events (KISS polling design).
                            if isinstance(obj, dict) and "request_id" in obj:
                                with self._resp_cv:
                                    self._responses[obj["request_id"]] = obj
                                    self._resp_cv.notify_all()
                        except Exception:
                            # ignore malformed JSON lines
                            pass
                except BlockingIOError:
                    time.sleep(0.05)
            except Exception:
                time.sleep(0.1)

    def _send(self, payload: Dict[str, Any]) -> None:
        if not self.sock:
            raise RuntimeError("mpv IPC not connected")
        data = (json.dumps(payload) + "\n").encode("utf-8")
        with self._lock:
            self.sock.sendall(data)

    def _next_id(self) -> int:
        with self._lock:
            self._req_id += 1
            return self._req_id

    # ---- commands ----
    def load(self, url: str):
        self.command(["loadfile", url, "replace"])

    def stop(self):
        self.command(["stop"])

    def pause(self, state: bool):
        self.set_property("pause", state)

    def set_volume(self, vol: int):
        self.set_property("volume", max(0, min(100, vol)))

    def get_prop(self, name: str, timeout: float = 0.5) -> Optional[Any]:
        """Request/response without touching unsolicited events."""
        reqid = self._next_id()
        self._send({"command": ["get_property", name], "request_id": reqid})
        end = time.time() + timeout
        with self._resp_cv:
            while time.time() < end and not self._stop_reader.is_set():
                if reqid in self._responses:
                    resp = self._responses.pop(reqid)
                    return resp.get("data")
                remaining = end - time.time()
                if remaining > 0:
                    self._resp_cv.wait(timeout=remaining)
        return None

    def set_property(self, name: str, value: Any):
        self.command(["set_property", name, value])

    def command(self, cmd_list):
        self._send({"command": cmd_list})

    def observe_property(self, name: str, obs_id: Optional[int] = None):
        if obs_id is None:
            obs_id = self._next_id()
        self._send({"command": ["observe_property", obs_id, name]})

    def is_running(self) -> bool:
        return self.proc is not None and self.proc.poll() is None

    def shutdown(self):
        try:
            if self.is_running():
                self.command(["quit"])
                time.sleep(0.2)
                if self.is_running():
                    self.proc.terminate()
        except Exception:
            pass
        self._stop_reader.set()
        try:
            if self.sock:
                self.sock.close()
        except Exception:
            pass
        try:
            if os.path.exists(self.ipc_path):
                os.unlink(self.ipc_path)
        except Exception:
            pass

# ------------------- Jukebox logic -------------------
class Jukebox:
    def __init__(self):
        # Fail-fast on startup if Redis isn't reachable
        self.r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, db=REDIS_DB,
                             decode_responses=True, socket_timeout=2, socket_connect_timeout=2)
        try:
            self.r.ping()
        except Exception as e:
            raise RuntimeError(f"Redis unavailable: {e}")

        self.mpv = MPV(IPC_PATH)
        self.current_song: Optional[Dict[str, Any]] = None
        self.desired_state = self._load_desired_state()  # playing|paused|stopped
        self._shutdown = threading.Event()

        # simple session for HTTP keepalive
        self.http = requests.Session()

    # API: ask Rails for the next song
    def get_next_song(self) -> Optional[Dict[str, Any]]:
        url = f"{API_BASE}/jukebox/player/next"
        try:
            res = self.http.get(url, timeout=5)
            if res.status_code == 200:
                return res.json()
            if res.status_code == 204:
                return None
            log.warning(f"next_song HTTP {res.status_code}")
        except requests.RequestException as e:
            log.warning(f"next_song error: {e}")
        return None

    def _load_desired_state(self) -> str:
        try:
            val = self.r.get(DESIRED)
            return val if val in ("playing","paused","stopped") else "stopped"
        except Exception:
            return "stopped"

    def _save_desired_state(self, state: str):
        try:
            self.r.set(DESIRED, state)
        except Exception:
            pass

    # Playback controls
    def play_url(self, url: str):
        self.mpv.load(url)
        self.mpv.pause(False)

    def pause(self):
        self.mpv.pause(True)

    def resume(self):
        self.mpv.pause(False)

    def stop(self):
        self.mpv.stop()

    def set_volume(self, vol: int):
        self.mpv.set_volume(vol)

    # Property reads (one-shot polls)
    def elapsed(self) -> float:
        v = self.mpv.get_prop("time-pos")
        return float(v) if v is not None else 0.0

    def duration(self) -> float:
        v = self.mpv.get_prop("duration")
        return float(v) if v is not None else 0.0

    def volume(self) -> int:
        v = self.mpv.get_prop("volume")
        try:
            return int(round(float(v)))
        except Exception:
            return VOLUME

    def idle_active(self) -> bool:
        try:
            val = self.mpv.get_prop("idle-active")
            return bool(val)
        except Exception:
            return False

    def paused_flag(self) -> bool:
        try:
            val = self.mpv.get_prop("pause")
            return bool(val)
        except Exception:
            return False

    def current_path(self) -> str:
        try:
            v = self.mpv.get_prop("path")
            return str(v) if v else ""
        except Exception:
            return ""

    # Status writer
    def write_status(self, extra_error: str = ""):
        try:
            idle = self.idle_active()
            paused = self.paused_flag()
            dur = self.duration()
            el  = self.elapsed()
            rem = max(0.0, (dur or 0) - (el or 0))
            progress = round((el / dur * 100.0), 1) if dur > 0 else 0.0
            actual_state = "stopped" if idle else ("paused" if paused else "playing")

            now = time.time()
            ts_unix = f"{now:.3f}"
            ts_iso = time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(now)) + f".{int((now%1)*1000):03d}Z"

            song = self.current_song or {}
            status = {
                "timestamp_unix": ts_unix,
                "timestamp_iso": ts_iso,
                "desired_state": self.desired_state,
                "actual_state": actual_state,
                "idle_active": "true" if idle else "false",
                "paused": "true" if paused else "false",
                "elapsed_seconds": f"{el:.3f}",
                "duration_seconds": f"{dur:.3f}",
                "remaining_seconds": f"{rem:.3f}",
                "progress_percent": f"{progress:.1f}",
                "volume": str(self.volume()),
                # Flattened song fields (extend freely)
                "song_id": str(song.get("id", "")),
                "song_title": str(song.get("title", "")),
                "song_artist": str(song.get("artist", "")),
                "song_album": str(song.get("album", "")),
                "song_stream_url": str(song.get("stream_url", "")),
                "error_message": extra_error,
                "health": "healthy" if not extra_error else "degraded",
            }
            self.r.hset(STATUS_KEY, mapping=status)
            if self.current_song:
                self.r.set(CUR_SONG, json.dumps(self.current_song))
        except Exception as e:
            log.warning(f"write_status failed: {e}")

    # -------- Command collapsing (priority + strict last-wins volume) --------
    def handle_commands_collapsed(self):
        """
        Drain the Redis list and collapse into a single effective command set:
          priority: play=1 < pause=2 < skip=3 < stop=4 (highest wins)
          volume: STRICT last-wins across all volume actions (set/up/down).
        Returns:
          { "state": "playing"|"paused"|"stopped"|None,
            "do_skip": bool,
            "volume_set": Optional[int],   # last was set_volume
            "volume_delta": int }          # last was up/down (+10 / -10)
        """
        highest = 0
        state_choice: Optional[str] = None
        do_skip = False

        # track only the most recent volume command we saw (last wins)
        last_volume_kind: Optional[str] = None   # "set" | "delta" | None
        last_volume_value: Optional[int] = None  # set: absolute 0..100; delta: +10/-10

        PRIORITY = {"play":1, "pause":2, "skip":3, "stop":4}

        processed = 0
        try:
            while True:
                raw = self.r.lpop(CMD_LIST)
                if raw is None:
                    break
                processed += 1
                try:
                    if isinstance(raw, bytes):
                        raw = raw.decode()
                    cmd = json.loads(raw)
                    action = str(cmd.get("action","")).lower()

                    if action in PRIORITY:
                        pr = PRIORITY[action]
                        if action == "skip":
                            do_skip = True
                            if pr > highest:
                                highest = pr
                                # state_choice unchanged
                        elif action == "stop":
                            if pr > highest:
                                highest = pr
                                state_choice = "stopped"
                        elif action == "pause":
                            if pr > highest:
                                highest = pr
                                state_choice = "paused"
                        elif action == "play":
                            if pr > highest:
                                highest = pr
                                state_choice = "playing"

                    elif action == "set_volume":
                        try:
                            v = int(cmd.get("value"))
                            v = max(0, min(100, v))
                            last_volume_kind  = "set"
                            last_volume_value = v
                        except Exception:
                            pass

                    elif action == "volume_up":
                        last_volume_kind  = "delta"
                        last_volume_value = 10

                    elif action == "volume_down":
                        last_volume_kind  = "delta"
                        last_volume_value = -10

                    else:
                        log.warning(f"Unknown command action discarded: {action}")

                except Exception as e:
                    log.error(f"Error parsing command {raw}: {e}")
                    continue
        except redis.ConnectionError as e:
            log.error(f"Redis error while reading commands: {e}")

        volume_set = None
        volume_delta = 0
        if last_volume_kind == "set" and last_volume_value is not None:
            volume_set = last_volume_value
        elif last_volume_kind == "delta" and last_volume_value is not None:
            volume_delta = last_volume_value

        if processed:
            vol_msg = f"set={volume_set}" if volume_set is not None else f"dV={volume_delta}"
            log.info(f"Collapsed {processed} cmd(s) -> state={state_choice}, skip={do_skip}, {vol_msg}")

        return {
            "state": state_choice,
            "do_skip": do_skip,
            "volume_set": volume_set,
            "volume_delta": volume_delta,
        }

    def run(self):
        # signals
        def _sig(_s,_f): self._shutdown.set()
        signal.signal(signal.SIGINT, _sig)
        signal.signal(signal.SIGTERM, _sig)

        log.info("Starting mpv…")
        self.mpv.start()
        log.info("Jukebox ready. Desired state: %s", self.desired_state)

        # Main loop (KISS: poll → collapse → reconcile → status)
        while not self._shutdown.is_set():
            loop_start = time.time()
            try:
                # 1) drain+collapse commands
                collapsed = self.handle_commands_collapsed()

                # apply skip immediately (doesn't change desired state)
                if collapsed["do_skip"]:
                    try:
                        self.stop()
                    except Exception:
                        pass

                # update desired state if provided
                if collapsed["state"] in ("playing","paused","stopped"):
                    self.desired_state = collapsed["state"]
                    self._save_desired_state(self.desired_state)

                # apply volume
                if collapsed["volume_set"] is not None:
                    self.set_volume(collapsed["volume_set"])
                elif collapsed["volume_delta"] != 0:
                    new_vol = max(0, min(100, self.volume() + collapsed["volume_delta"]))
                    self.set_volume(new_vol)

                # 2) reconcile actual vs desired (using idle-active/pause)
                idle = self.idle_active()
                paused = self.paused_flag()

                if self.desired_state == "playing":
                    if idle:
                        ns = self.get_next_song()
                        if ns and ns.get("stream_url"):
                            self.current_song = ns
                            self.play_url(ns["stream_url"])
                        else:
                            # No track to play; transition to 'stopped' to avoid spamming the queue
                            self.desired_state = "stopped"
                            self._save_desired_state(self.desired_state)
                            log.info("No next song; transitioning desired_state -> stopped")
                    else:
                        if paused:
                            self.resume()

                elif self.desired_state == "paused":
                    # Pause only if something is loaded and not already paused
                    if not idle and not paused:
                        self.pause()

                elif self.desired_state == "stopped":
                    if not idle:
                        self.stop()
                        # Keep last current_song visible

                # 3) write status last
                self.write_status()

            except Exception as e:
                log.error(f"Loop error: {e}")
                self.write_status(str(e))

            # ~1s cadence
            dt = time.time() - loop_start
            # use Event.wait so signals stop us promptly
            self._shutdown.wait(timeout=max(0, 1.0 - dt))

        # cleanup
        try:
            self.stop()
        except Exception:
            pass
        self.mpv.shutdown()
        log.info("Shutdown complete.")

# ------------------- entry -------------------
if __name__ == "__main__":
    try:
        Jukebox().run()
    except KeyboardInterrupt:
        log.info("Shutting down…")
        sys.exit(0)
