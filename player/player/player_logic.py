import json
import time
import logging
import threading
from typing import Optional, Dict, Any
import redis
import requests

from .config import settings
from .mpv import MPV

log = logging.getLogger("player.logic")

class Player:
    def __init__(self):
        try:
            self.r = redis.Redis(
                host=settings.REDIS_HOST, port=settings.REDIS_PORT, db=settings.REDIS_DB,
                decode_responses=True, socket_timeout=2, socket_connect_timeout=2
            )
            self.r.ping()
        except redis.exceptions.ConnectionError as e:
            log.critical(f"Redis is unavailable at {settings.REDIS_HOST}:{settings.REDIS_PORT}. Exiting.")
            raise RuntimeError(f"Redis unavailable: {e}")

        self.mpv = MPV(settings.MPV_SOCKET)
        self.current_song: Optional[Dict[str, Any]] = None
        self.desired_state = self._load_desired_state()
        self._shutdown = threading.Event()
        self.http = requests.Session()

    def get_next_song(self) -> Optional[Dict[str, Any]]:
        url = f"{settings.API_URL}/jukebox/player/next"
        try:
            res = self.http.get(url, timeout=5)
            res.raise_for_status()
            if res.status_code == 204:
                return None  # No Content
            return res.json()
        except requests.RequestException as e:
            log.warning(f"API request for next song failed: {e}")
        return None

    def _load_desired_state(self) -> str:
        try:
            val = self.r.get(settings.DESIRED)
            if val in ("playing", "paused", "stopped"):
                return val
            else:
                return "stopped"
        except redis.exceptions.RedisError as e:
            log.error(f"Failed to load desired state from Redis: {e}")
            return "stopped"

    def _save_desired_state(self, state: str):
        try:
            self.r.set(settings.DESIRED, state)
        except redis.exceptions.RedisError as e:
            log.error(f"Failed to save state to Redis: {e}")

    def write_status(self, extra_error: str = ""):
        try:
            idle = self.mpv.get_prop("idle-active", 0.2) or False
            paused = self.mpv.get_prop("pause", 0.2) or False
            dur = float(self.mpv.get_prop("duration", 0.2) or 0.0)
            el = float(self.mpv.get_prop("time-pos", 0.2) or 0.0)
            vol = self.mpv.get_prop("volume", 0.2) or settings.VOLUME

            if idle:
                actual_state = "stopped"
            elif paused:
                actual_state = "paused"
            else:
                actual_state = "playing"
            
            now = time.time()
            song = self.current_song or {}

            status = {
                "timestamp_unix": f"{now:.3f}",
                "desired_state": self.desired_state,
                "actual_state": actual_state,
                "duration_seconds": f"{dur:.3f}",
                "elapsed_seconds": f"{el:.3f}",
                "progress_percent": f"{(el / dur * 100.0):.1f}" if dur > 0 else "0.0",
                "volume": str(int(round(float(vol)))),
                "song_id": str(song.get("id", "")),
                "song_title": str(song.get("title", "")),
                "song_artist": str(song.get("artist", "")),
                "song_album": str(song.get("album", "")),
                "health": "healthy" if not extra_error else "degraded",
                "error_message": extra_error
            }
            self.r.hset(settings.STATUS_KEY, mapping=status)
            if self.current_song:
                self.r.set(settings.CUR_SONG, json.dumps(self.current_song))
            else:
                self.r.delete(settings.CUR_SONG)

        except redis.exceptions.RedisError as e:
            log.warning(f"write_status failed: {e}")

    def handle_commands(self):
        PRIORITY = {"play": 1, "pause": 2, "skip": 3, "stop": 4}
        prio = 0
        state = None
        skip = False
        vol_kind = None
        vol_val = None

        try:
            commands = self.r.lrange(settings.CMD_LIST, 0, -1)
            if not commands:
                return {"state": None, "skip": False, "vol_set": None, "vol_delta": 0}

            self.r.ltrim(settings.CMD_LIST, len(commands), -1)

            for raw in commands:
                try:
                    cmd = json.loads(raw)
                    action = str(cmd.get("action", "")).lower()
                    if action in PRIORITY and PRIORITY[action] > prio:
                        prio = PRIORITY[action]
                        if action == "skip":
                            skip = True
                        else:
                            state = {"play": "playing", "pause": "paused", "stop": "stopped"}[action]
                    elif action == "set_volume":
                        vol_kind = "set"
                        vol_val = int(cmd.get("value"))
                    elif action == "volume_up":
                        vol_kind = "delta"
                        vol_val = 10
                    elif action == "volume_down":
                        vol_kind = "delta"
                        vol_val = -10
                except (json.JSONDecodeError, ValueError) as e:
                    log.error(f"Parsing cmd '{raw}': {e}")

            if vol_kind == "set" and vol_val is not None:
                vol_set = max(0, min(100, vol_val))
            else:
                vol_set = None
            
            if vol_kind == "delta" and vol_val is not None:
                vol_delta = vol_val
            else:
                vol_delta = 0

            log.info(f"Collapsed {len(commands)} cmds -> state={state}, skip={skip}, vol_set={vol_set}, vol_delta={vol_delta}")
            return {"state": state, "skip": skip, "vol_set": vol_set, "vol_delta": vol_delta}

        except redis.exceptions.RedisError as e:
            log.error(f"Redis error reading commands: {e}")
            return {"state": None, "skip": False, "vol_set": None, "vol_delta": 0}

    def run(self):
        log.info("Starting mpv...")
        self.mpv.start()
        log.info("Player ready. Initial desired state: %s", self.desired_state)

        while not self._shutdown.is_set():
            loop_start = time.time()
            error_msg = ""
            try:
                cmd = self.handle_commands()
                if cmd["skip"]:
                    self.mpv.stop()
                    self.current_song = None
                if cmd["state"]:
                    self.desired_state = cmd["state"]
                    self._save_desired_state(self.desired_state)
                if cmd["vol_set"] is not None:
                    self.mpv.set_volume(cmd["vol_set"])
                elif cmd["vol_delta"]:
                    current_vol = self.mpv.get_prop("volume", 0.2) or settings.VOLUME
                    self.mpv.set_volume(max(0, min(100, current_vol + cmd["vol_delta"])))

                idle = self.mpv.get_prop("idle-active", 0.2) or False
                paused = self.mpv.get_prop("pause", 0.2) or False

                if self.desired_state == "playing":
                    if idle:
                        song = self.get_next_song()
                        if song and song.get("stream_url"):
                            self.current_song = song
                            stream_url = settings.patch_stream_url(song.get("stream_url"))

                            self.mpv.load(stream_url)
                            log.info("Playing next song: %s url:%s", song["title"], stream_url)
                        else:
                            self.desired_state = "stopped"
                            self._save_desired_state("stopped")
                            log.info("No next song; transitioning to 'stopped' state.")
                    elif paused:
                        self.mpv.pause(False)
                elif self.desired_state == "paused" and not idle and not paused:
                    self.mpv.pause(True)
                elif self.desired_state == "stopped" and not idle:
                    self.mpv.stop()
                    self.current_song = None
            except Exception as e:
                log.error(f"Main loop error: {e}", exc_info=True)
                error_msg = str(e)

            self.write_status(error_msg)
            self._shutdown.wait(timeout=max(0, 1.0 - (time.time() - loop_start)))

    def shutdown(self):
        log.info("Shutdown initiated...")
        self._shutdown.set()
        self.mpv.shutdown()
        log.info("Shutdown complete.")
