import os, json, time, socket, subprocess, threading, logging
from typing import Optional, Dict, Any

from .config import settings

log = logging.getLogger("player.mpv")

class MPV:
    """
    Minimal mpv JSON IPC helper.
    Spawns mpv and communicates over a UNIX socket.
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
        if os.path.exists(self.ipc_path):
            try:
                os.unlink(self.ipc_path)
            except OSError as e:
                log.warning(f"Could not remove stale socket file: {e}")

        args = [
            "mpv", "--no-video", "--idle=yes", "--force-window=no",
            f"--input-ipc-server={self.ipc_path}",
            f"--volume={settings.VOLUME}",
            "--audio-client-name=player",
            "--ytdl=no", "--term-status-msg=",
            "--cache=yes", f"--cache-secs={settings.CACHE_SECS}",
        ]
        try:
            self.proc = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except FileNotFoundError:
            log.critical("mpv executable not found in PATH. Please install mpv.")
            raise RuntimeError("mpv executable not found in PATH")
        except Exception as e:
            raise RuntimeError(f"Failed to start mpv: {e}")

        # Wait for the socket to be created by mpv
        for _ in range(50):  # ~5s timeout
            if os.path.exists(self.ipc_path):
                try:
                    self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                    self.sock.connect(self.ipc_path)
                    self.sock.setblocking(True)
                    break
                except (ConnectionRefusedError, FileNotFoundError):
                    time.sleep(0.1)
                except Exception as e:
                    log.error(f"Error connecting to mpv socket: {e}")
                    time.sleep(0.1)
        if not self.sock:
            raise RuntimeError("Failed to connect to mpv IPC socket")

        self.reader_thread = threading.Thread(target=self._reader, daemon=True, name="MPVReader")
        self.reader_thread.start()

        for prop in ("time-pos", "duration", "pause", "volume", "idle-active", "path"):
            self.observe_property(prop)

    def _reader(self):
        buf = b""
        while not self._stop_reader.is_set():
            try:
                if self.proc and self.proc.poll() is not None:
                    with self._resp_cv:
                        self._stop_reader.set()
                        self._resp_cv.notify_all()
                    return
                if not self.sock: time.sleep(0.05); continue

                chunk = self.sock.recv(4096)
                if not chunk: time.sleep(0.05); continue

                buf += chunk
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    if not (line := line.strip()): continue
                    try:
                        obj = json.loads(line.decode("utf-8", "replace"))
                        if isinstance(obj, dict) and "request_id" in obj:
                            with self._resp_cv:
                                self._responses[obj["request_id"]] = obj
                                self._resp_cv.notify_all()
                    except json.JSONDecodeError:
                        log.warning(f"Malformed JSON from mpv: {line.decode()}")
            except (socket.timeout, BlockingIOError):
                time.sleep(0.05)
            except Exception as e:
                log.error(f"MPV reader thread error: {e}")
                time.sleep(0.1)

    def _send(self, payload: Dict[str, Any]) -> None:
        if not self.sock: raise RuntimeError("mpv IPC not connected")
        data = (json.dumps(payload) + "\n").encode("utf-8")
        with self._lock:
            self.sock.sendall(data)

    def _next_id(self) -> int:
        with self._lock: self._req_id += 1; return self._req_id

    def command(self, cmd_list: list): self._send({"command": cmd_list})
    def set_property(self, name: str, value: Any): self.command(["set_property", name, value])

    def get_prop(self, name: str, timeout: float = 0.5) -> Optional[Any]:
        reqid = self._next_id()
        self._send({"command": ["get_property", name], "request_id": reqid})
        end = time.time() + timeout
        with self._resp_cv:
            while time.time() < end and not self._stop_reader.is_set():
                if reqid in self._responses:
                    return self._responses.pop(reqid).get("data")
                remaining = end - time.time()
                if remaining > 0: self._resp_cv.wait(timeout=remaining)
        return None

    def observe_property(self, name: str): self.command(["observe_property", self._next_id(), name])
    def is_running(self) -> bool: return self.proc is not None and self.proc.poll() is None

    def shutdown(self):
        try:
            if self.is_running():
                self.command(["quit"])
                if self.proc:
                    try: self.proc.wait(timeout=1.0)
                    except subprocess.TimeoutExpired: self.proc.terminate()
        except Exception as e:
            log.warning(f"Error during mpv shutdown command: {e}")
        finally:
            self._stop_reader.set()
            if self.sock: self.sock.close()
            if os.path.exists(self.ipc_path):
                try: os.unlink(self.ipc_path)
                except OSError: pass

    def load(self, url: str): self.command(["loadfile", url, "replace"])
    def stop(self): self.command(["stop"])
    def pause(self, state: bool): self.set_property("pause", state)
    def set_volume(self, vol: int): self.set_property("volume", max(0, min(100, vol)))