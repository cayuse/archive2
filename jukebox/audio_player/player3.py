#!/usr/bin/env python3
import os, sys, json, time, socket, subprocess, threading, queue, logging
from pathlib import Path
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
CACHE_SECS = int(os.getenv("JUKEBOX_CACHE_SECS", "20"))      # mpv read-ahead cache
STATUS_KEY = "jukebox:player_status"
CMD_LIST   = "jukebox:commands"
CUR_SONG   = "jukebox:current_song"
DESIRED    = "jukebox:desired_state"  # playing|paused|stopped

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s"
)
log = logging.getLogger("jukebox")

# ------------------- mpv JSON IPC -------------------
class MPV:
    """
    Small helper for mpv JSON IPC.
    We spawn mpv with --input-ipc-server=IPC_PATH and talk JSON over a UNIX socket.
    """
    def __init__(self, ipc_path: str):
        self.ipc_path = ipc_path
        self.proc: Optional[subprocess.Popen] = None
        self.sock: Optional[socket.socket] = None
        self.reader_thread: Optional[threading.Thread] = None
        self.events = queue.Queue()  # JSON events from mpv (end-file, property-change, etc.)
        self._req_id = 0
        self._lock = threading.Lock()

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
            f"--cache=yes",
            f"--cache-secs={CACHE_SECS}"
        ]
        self.proc = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        # wait for socket
        for _ in range(50):  # ~5s
            try:
                self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                self.sock.connect(self.ipc_path)
                self.sock.setblocking(False)
                break
            except Exception:
                time.sleep(0.1)
        if not self.sock:
            raise RuntimeError("Failed to connect to mpv IPC socket")

        # start reader thread
        self.reader_thread = threading.Thread(target=self._reader, daemon=True)
        self.reader_thread.start()

        # Observe time-pos & duration so we can get push events if desired
        self.observe_property("time-pos")
        self.observe_property("duration")
        self.observe_property("pause")
        self.observe_property("volume")

    def _reader(self):
        buf = b""
        while True:
            try:
                if self.proc and self.proc.poll() is not None:
                    # mpv exited
                    self.events.put({"event": "process-exit"})
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
                            self.events.put(obj)
                        except Exception:
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

    def get_prop(self, name: str) -> Optional[Any]:
        reqid = self._next_id()
        self._send({"command": ["get_property", name], "request_id": reqid})
        # poll events queue for response with matching request_id
        deadline = time.time() + 0.5
        while time.time() < deadline:
            try:
                evt = self.events.get(timeout=0.05)
            except queue.Empty:
                continue
            if evt.get("request_id") == reqid:
                return evt.get("data")
            else:
                # push back non-matching events
                self.events.put(evt)
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

# ------------------- Jukebox logic -------------------
class Jukebox:
    def __init__(self):
        self.r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, db=REDIS_DB)
        self.mpv = MPV(IPC_PATH)
        self.current_song: Optional[Dict[str, Any]] = None
        self.desired_state = self._load_desired_state()  # playing|paused|stopped

    # API: ask Rails for the next song
    def get_next_song(self) -> Optional[Dict[str, Any]]:
        url = f"{API_BASE}/jukebox/player/next"
        for attempt in range(3):
            try:
                res = requests.get(url, timeout=5)
                if res.status_code == 200:
                    return res.json()
                if res.status_code == 204:
                    return None
                log.warning(f"next_song HTTP {res.status_code}")
            except requests.RequestException as e:
                log.warning(f"next_song attempt {attempt+1} failed: {e}")
                time.sleep(1)
        return None

    def _load_desired_state(self) -> str:
        try:
            raw = self.r.get(DESIRED)
            val = raw.decode() if raw else "stopped"
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

    # Helpers
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

    def write_status(self, extra_error: str = ""):
        try:
            dur = self.duration()
            el  = self.elapsed()
            rem = max(0.0, (dur or 0) - (el or 0))
            progress = round((el / dur * 100.0), 1) if dur > 0 else 0.0
            paused = bool(self.mpv.get_prop("pause"))
            idle_active = bool(self.mpv.get_prop("idle-active"))
            actual_state = "stopped" if idle_active else ("paused" if paused else "playing")
            status = {
                "timestamp": str(time.time()),
                "desired_state": self.desired_state,
                "actual_state": actual_state,
                "elapsed_seconds": f"{el:.3f}",
                "duration_seconds": f"{dur:.3f}",
                "remaining_seconds": f"{rem:.3f}",
                "progress_percent": f"{progress:.1f}",
                "volume": str(self.volume()),
                "current_song_metadata": json.dumps(self.current_song or {}),
                "error_message": extra_error,
                "health": "healthy" if not extra_error else "degraded",
            }
            self.r.hset(STATUS_KEY, mapping=status)
            if self.current_song:
                self.r.set(CUR_SONG, json.dumps(self.current_song))
        except Exception as e:
            log.warning(f"write_status failed: {e}")

    def handle_commands(self):
        """Process commands from Redis queue one by one"""
        try:
            # Process commands one at a time to maintain proper order
            processed_count = 0
            while True:
                # Get one command from the front of the queue
                raw_cmd = self.r.lpop(CMD_LIST)
                if not raw_cmd:
                    break  # No more commands
                
                processed_count += 1
                log.info(f"Processing command #{processed_count}: {raw_cmd}")
                
                try:
                    cmd = json.loads(raw_cmd.decode() if isinstance(raw_cmd, bytes) else raw_cmd)
                    action = cmd.get("action")
                    log.info(f"Executing action: {action}")
                    
                    # Process each command individually
                    if action == "play":
                        self.desired_state = "playing"
                        if self.duration() == 0:
                            ns = self.get_next_song()
                            if ns and ns.get("stream_url"):
                                self.current_song = ns
                                self.play_url(ns["stream_url"])
                        else:
                            self.resume()
                        self._save_desired_state(self.desired_state)
                        log.info(f"Play command completed - desired_state: {self.desired_state}")
                        
                    elif action == "pause":
                        self.desired_state = "paused"
                        self.pause()
                        self._save_desired_state(self.desired_state)
                        log.info(f"Pause command completed - desired_state: {self.desired_state}")
                        
                    elif action == "stop":
                        self.desired_state = "stopped"
                        self.stop()
                        self._save_desired_state(self.desired_state)
                        log.info(f"Stop command completed - desired_state: {self.desired_state}")
                        
                    elif action == "skip":
                        log.info("Skip command received - loading next song")

                        # Stop current track explicitly and immediately load next
                        try:
                            self.stop()
                        except Exception:
                            pass
                        ns = self.get_next_song()
                        if ns and ns.get("stream_url"):
                            self.current_song = ns
                            self.play_url(ns["stream_url"])
                            self.desired_state = "playing"
                            self._save_desired_state(self.desired_state)
                            log.info(f"Skip command completed - loaded: {ns.get('title', 'Unknown')}")
                        else:
                            log.warning("No next song available for skip")
                            
                    elif action == "set_volume":
                        vol = int(cmd.get("value", self.volume()))
                        vol = max(0, min(100, vol))  # Clamp to 0-100
                        self.set_volume(vol)
                        log.info(f"Volume set to {vol}%")
                        
                    elif action == "volume_up":
                        current_vol = self.volume()
                        new_vol = min(100, current_vol + 10)
                        self.set_volume(new_vol)
                        log.info(f"Volume increased to {new_vol}%")
                        
                    elif action == "volume_down":
                        current_vol = self.volume()
                        new_vol = max(0, current_vol - 10)
                        self.set_volume(new_vol)
                        log.info(f"Volume decreased to {new_vol}%")
                        
                    else:
                        log.warning(f"Unknown command action: {action}")
                        
                except Exception as e:
                    log.error(f"Error processing command {raw_cmd}: {e}")
                    continue
            
            if processed_count > 0:
                log.info(f"Processed {processed_count} commands from queue")
                
                # Verify queue is empty
                remaining_cmds = self.r.llen(CMD_LIST)
                if remaining_cmds > 0:
                    log.warning(f"Queue still has {remaining_cmds} commands after processing!")
                    # Log what's still in the queue
                    remaining = self.r.lrange(CMD_LIST, 0, -1)
                    for i, cmd in enumerate(remaining):
                        log.warning(f"Remaining command {i}: {cmd}")
                else:
                    log.info("Queue is empty after processing")

        except Exception as e:
            log.warning(f"handle_commands error: {e}")

    def is_idle(self) -> bool:
        """Return True if mpv is idle (no file loaded or stopped)."""
        try:
            val = self.mpv.get_prop("idle-active")
            return bool(val)
        except Exception:
            return False

    def run(self):
        log.info("Starting mpv…")
        self.mpv.start()
        log.info("Jukebox ready. Desired state: %s", self.desired_state)

        # If desired state is 'playing', kick off first track
        if self.desired_state == "playing" and self.is_idle():
            ns = self.get_next_song()
            if ns and ns.get("stream_url"):
                self.current_song = ns
                self.play_url(ns["stream_url"])

        # Main loop
        while True:
            loop_start = time.time()
            try:
                # 1) process commands
                self.handle_commands()

                # 2) state machine: ensure actual playback matches desired state
                idle = self.is_idle()
                paused = bool(self.mpv.get_prop("pause"))
                if self.desired_state == "playing":
                    # If idle (stopped), fetch next and play
                    if idle:
                        ns = self.get_next_song()
                        if ns and ns.get("stream_url"):
                            self.current_song = ns
                            self.play_url(ns["stream_url"])
                        else:
                            # No track to play; remain stopped
                            pass
                    else:
                        # Ensure we are not paused
                        if paused:
                            self.resume()
                elif self.desired_state == "paused":
                    if not paused and not idle:
                        self.pause()
                elif self.desired_state == "stopped":
                    if not idle:
                        self.stop()

                # 3) write status last
                self.write_status()
            except Exception as e:
                log.error(f"Loop error: {e}")
                self.write_status(str(e))
            # ~1s cadence
            dt = time.time() - loop_start
            time.sleep(max(0, 1.0 - dt))

# ------------------- entry -------------------
if __name__ == "__main__":
    try:
        Jukebox().run()
    except KeyboardInterrupt:
        log.info("Shutting down…")
        sys.exit(0)
