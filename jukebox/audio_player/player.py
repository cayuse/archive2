#!/usr/bin/env python3
"""
Music Player Controller for Jukebox System
Uses MPD for audio playback via TCP (host.docker.internal:6600), Redis for state/commands, HTTP to Rails for next song
Single-threaded loop: process commands, poll MPD, report status, sleep ~1s
"""

import os
import time
import json
import logging
from pathlib import Path
from typing import Dict, Optional
import redis
import requests
from mpd import MPDClient, ConnectionError, CommandError

# Configure logging
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)
_formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
_handlers = [logging.StreamHandler()]
_log_file = os.getenv('JUKEBOX_LOG_FILE', '/var/log/jukebox_player.log')
try:
    _fh = logging.FileHandler(_log_file)
except Exception:
    try:
        _fh = logging.FileHandler(str(Path.home() / 'jukebox_player.log'))
    except Exception:
        _fh = logging.FileHandler('/tmp/jukebox_player.log')
if _fh:
    _fh.setFormatter(_formatter)
    _handlers.append(_fh)
for _h in _handlers:
    _h.setFormatter(_formatter)
    logger.addHandler(_h)

class JukeboxPlayer:
    """Jukebox player controller using MPD and Redis"""

    def __init__(self):
        self.config = self.load_config()
        self.redis_client = redis.Redis(
            host=self.config['redis_host'],
            port=self.config['redis_port'],
            db=self.config['redis_db']
        )
        self.mpd_client = None
        self.desired_state = self._load_desired_state()
        self.current_song = None
        self.is_playing = False
        self.connect_mpd()

    def load_config(self) -> Dict:
        """Load configuration from env vars"""
        return {
            'redis_host': os.getenv('REDIS_HOST', 'redis'),
            'redis_port': int(os.getenv('REDIS_PORT', '6379')),
            'redis_db': int(os.getenv('REDIS_DB', '1')),
            'jukebox_api_url': os.getenv('JUKEBOX_API_URL', 'http://jukebox:3001/api'),
            'crossfade_duration': 6,
            'prequeue_margin': 3,
            'volume': 80,
            'retry_attempts': 3,
            'retry_delay': 1
        }

    def connect_mpd(self):
        """Connect to MPD daemon via TCP"""
        try:
            self.mpd_client = MPDClient()
            self.mpd_client.connect('host.docker.internal', 6600)  # TCP via host
            logger.info("Connected to MPD via TCP host.docker.internal:6600")
            try:
                outs = self.mpd_client.outputs()
                for o in outs or []:
                    if o.get('outputenabled') == '0':
                        self.mpd_client.enableoutput(int(o.get('outputid', 0)))
            except Exception:
                pass
            try:
                self.mpd_client.crossfade(self.config['crossfade_duration'])
                self.mpd_client.setvol(self.config['volume'])
                self.mpd_client.repeat(0)
                self.mpd_client.random(0)
                self.mpd_client.single(0)
                self.mpd_client.consume(1)
            except Exception as e:
                logger.error(f"Failed to set MPD config: {e}")
        except (ConnectionError, CommandError) as e:
            logger.error(f"MPD connection failed: {e}")
            raise

    def reconnect_mpd(self):
        """Reconnect to MPD if disconnected"""
        try:
            self.mpd_client.disconnect()
        except Exception:
            pass
        time.sleep(self.config['retry_delay'])
        self.connect_mpd()

    def _load_desired_state(self) -> str:
        """Load desired state from Redis"""
        try:
            raw = self.redis_client.get('jukebox:desired_state')
            state = raw.decode('utf-8') if raw else 'stopped'
            if state not in ('playing', 'paused', 'stopped'):
                state = 'stopped'
            return state
        except Exception as e:
            logger.error(f"Error loading desired state: {e}")
            return 'stopped'

    def _save_desired_state(self):
        """Save desired state to Redis"""
        try:
            self.redis_client.set('jukebox:desired_state', self.desired_state)
        except Exception as e:
            logger.error(f"Error saving desired state: {e}")

    def get_next_song(self) -> Optional[Dict]:
        """Fetch next song from Rails API"""
        try:
            url = f"{self.config['jukebox_api_url']}/jukebox/player/next"
            for attempt in range(self.config['retry_attempts']):
                try:
                    resp = requests.get(url, timeout=5)
                    if resp.status_code == 200:
                        song_data = resp.json()
                        logger.info(f"Next song: {song_data.get('title', 'Unknown')} (id={song_data.get('id')})")
                        return song_data
                    elif resp.status_code == 204:
                        logger.info("No next song available")
                        return None
                    logger.warning(f"Next song request failed: {resp.status_code}")
                except requests.RequestException as e:
                    logger.warning(f"Next song attempt {attempt+1} failed: {e}")
                    if attempt < self.config['retry_attempts'] - 1:
                        time.sleep(self.config['retry_delay'])
            return None
        except Exception as e:
            logger.error(f"Error fetching next song: {e}")
            return None

    def play_song(self, song_data: Dict, force_play: bool = False):
        """Play song via MPD using stream_url only"""
        try:
            stream_url = song_data.get('stream_url')
            if not stream_url:
                logger.error(f"No stream_url for song {song_data.get('id')}")
                return False
            status = self.mpd_client.status()
            playlist_length = int(status.get('playlistlength', '0')) if status else 0
            if force_play or playlist_length == 0:
                self.mpd_client.clear()
                self.mpd_client.add(stream_url)
                self.mpd_client.play()
                logger.info(f"Playing {song_data.get('title', 'Unknown')} (force={force_play})")
            else:
                self.mpd_client.add(stream_url)
                logger.info(f"Queued {song_data.get('title', 'Unknown')}")
            self.current_song = song_data
            self.is_playing = True
            try:
                self.redis_client.set('jukebox:current_song', json.dumps(song_data))
            except Exception as e:
                logger.error(f"Error saving current song to Redis: {e}")
            return True
        except Exception as e:
            logger.error(f"Error playing song: {e}")
            return False

    def collapse_commands(self, commands: list) -> Dict:
        """Collapse command queue into action plan"""
        action_plan = {}
        state_priority = {'play': 1, 'pause': 2, 'stop': 3}
        for cmd in commands:
            try:
                cmd_data = json.loads(cmd.decode('utf-8') if isinstance(cmd, bytes) else cmd)
                action = cmd_data.get('action')
                if action in ('play', 'pause', 'stop'):
                    current_priority = state_priority.get(action_plan.get('state_action', None), 0)
                    if state_priority.get(action, 0) >= current_priority:
                        action_plan['state_action'] = action
                elif action in ('set_volume', 'volume_up', 'volume_down'):
                    action_plan['volume_action'] = cmd_data  # Last wins
                elif action == 'set_crossfade':
                    action_plan['crossfade_action'] = cmd_data
            except Exception as e:
                logger.error(f"Invalid command: {cmd}, error: {e}")
        return action_plan

    def execute_action_plan(self, action_plan: Dict):
        """Execute collapsed commands on MPD"""
        try:
            # State commands
            if 'state_action' in action_plan:
                action = action_plan['state_action']
                if action == 'stop':
                    self.desired_state = 'stopped'
                    self.mpd_client.stop()
                    self.is_playing = False
                    self.current_song = None
                elif action == 'pause':
                    status = self.mpd_client.status()
                    if status.get('state') in ('stop', 'pause'):
                        # Pause means play if not playing
                        self.desired_state = 'playing'
                        if not self.play_song(self.get_next_song(), force_play=True):
                            self.desired_state = 'stopped'
                            self.mpd_client.stop()
                    else:
                        self.desired_state = 'paused'
                        self.mpd_client.pause(1)
                        self.is_playing = False
                elif action == 'play':
                    self.desired_state = 'playing'
                    status = self.mpd_client.status()
                    if status.get('state') == 'pause':
                        self.mpd_client.pause(0)
                        self.is_playing = True
                    elif status.get('state') != 'play':
                        if not self.play_song(self.get_next_song(), force_play=True):
                            self.desired_state = 'stopped'
                            self.mpd_client.stop()
                self._save_desired_state()

            # Volume commands (last wins)
            if 'volume_action' in action_plan:
                cmd = action_plan['volume_action']
                action = cmd.get('action')
                current_volume = int(self.mpd_client.status().get('volume', '0') or 0)
                if action == 'set_volume':
                    volume = max(0, min(100, int(cmd.get('value', current_volume))))
                elif action == 'volume_up':
                    volume = min(100, current_volume + 10)
                elif action == 'volume_down':
                    volume = max(0, current_volume - 10)
                try:
                    self.mpd_client.setvol(volume)
                    self.redis_client.set('jukebox:current_volume', volume)
                    logger.info(f"Volume set to {volume}")
                except Exception as e:
                    logger.error(f"Error setting volume: {e}")

            # Crossfade
            if 'crossfade_action' in action_plan:
                duration = int(max(0, min(100, action_plan['crossfade_action'].get('value', 0))))
                try:
                    self.mpd_client.crossfade(duration)
                    logger.info(f"Crossfade set to {duration}s")
                except Exception as e:
                    logger.error(f"Error setting crossfade: {e}")

        except Exception as e:
            logger.error(f"Error executing action plan: {e}")

    def update_status(self):
        """Poll MPD and write status to Redis"""
        try:
            status = self.mpd_client.status()
            actual_state = status.get('state', 'stop')
            elapsed = float(status.get('elapsed', '0') or 0)
            duration = float(status.get('duration', '0') or 0)
            if not duration and status.get('time'):
                try:
                    parts = status.get('time').split(':')
                    elapsed = float(parts[0])
                    duration = float(parts[1])
                except Exception:
                    pass
            remaining = max(0.0, duration - elapsed) if duration else 0.0
            progress = round((elapsed / duration * 100) if duration > 0 else 0, 1)
            volume = int(status.get('volume', '0') or 0)
            crossfade = int(status.get('xfade', '0') or 0)
            playlist_length = int(status.get('playlistlength', '0') or 0)
            error_message = ''
            health = 'healthy'

            # Reconcile desired vs actual state
            if actual_state != self.desired_state:
                if self.desired_state == 'playing' and actual_state != 'play':
                    if not self.play_song(self.get_next_song(), force_play=True):
                        self.desired_state = 'stopped'
                        self.mpd_client.stop()
                        error_message = 'No next song available'
                elif self.desired_state == 'paused' and actual_state == 'play':
                    self.mpd_client.pause(1)
                    self.is_playing = False
                elif self.desired_state == 'stopped':
                    self.mpd_client.stop()
                    self.is_playing = False
                    self.current_song = None
                self._save_desired_state()

            # Check for next song
            threshold = self.config['crossfade_duration'] + self.config['prequeue_margin']
            if self.desired_state == 'playing' and actual_state == 'play' and playlist_length <= 1 and remaining <= threshold:
                if not self.play_song(self.get_next_song(), force_play=False):
                    self.desired_state = 'stopped'
                    self.mpd_client.stop()
                    error_message = 'No next song available'

            # Write status
            status_data = {
                'timestamp': str(time.time()),
                'desired_state': self.desired_state,
                'actual_state': actual_state,
                'elapsed_seconds': str(elapsed),
                'duration_seconds': str(duration),
                'volume': str(volume),
                'crossfade_seconds': str(crossfade),
                'time_until_next_request': str(max(0, remaining - threshold) if actual_state == 'play' else 0),
                'current_song_metadata': json.dumps(self.current_song or {}),
                'error_message': error_message,
                'health': health if self.mpd_client.ping() else 'unhealthy',
                'remaining_seconds': str(remaining),
                'progress_percent': str(progress)
            }
            try:
                self.redis_client.hset('jukebox:player_status', mapping=status_data)
            except Exception as e:
                logger.error(f"Error writing status to Redis: {e}")

        except Exception as e:
            logger.error(f"Error polling MPD: {e}")
            self.reconnect_mpd()
            status_data = {
                'timestamp': str(time.time()),
                'desired_state': self.desired_state,
                'actual_state': 'stop',
                'elapsed_seconds': '0',
                'duration_seconds': '0',
                'volume': '0',
                'crossfade_seconds': str(self.config['crossfade_duration']),
                'time_until_next_request': '0',
                'current_song_metadata': '{}',
                'error_message': str(e),
                'health': 'unhealthy',
                'remaining_seconds': '0',
                'progress_percent': '0'
            }
            try:
                self.redis_client.hset('jukebox:player_status', mapping=status_data)
            except Exception as e:
                logger.error(f"Error writing error status to Redis: {e}")

    def run(self):
        """Main loop: process commands, execute, poll, report, sleep ~1s"""
        logger.info("Starting Jukebox Player")
        logger.info(f"Using API base: {self.config.get('jukebox_api_url')}")
        try:
            self.redis_client.set('jukebox:status', json.dumps({
                'state': 'starting',
                'timestamp': time.time()
            }))
            while True:
                start_time = time.time()
                # Step 1: Pull and collapse commands
                try:
                    commands = self.redis_client.lrange('jukebox:commands', 0, -1)
                    if commands:
                        self.redis_client.delete('jukebox:commands')
                        action_plan = self.collapse_commands(commands)
                        # Step 2: Execute action plan
                        self.execute_action_plan(action_plan)
                except Exception as e:
                    logger.error(f"Error processing commands: {e}")
                # Step 3: Poll and update status
                self.update_status()
                # Step 4: Sleep to ~1s
                elapsed = time.time() - start_time
                time.sleep(max(0, 1 - elapsed))
        except KeyboardInterrupt:
            logger.info("Shutdown requested")
        except Exception as e:
            logger.error(f"Unexpected error: {e}")
        finally:
            self.shutdown()

    def shutdown(self):
        """Clean shutdown"""
        logger.info("Shutting down Jukebox Player")
        try:
            if self.mpd_client:
                self.mpd_client.stop()
                self.mpd_client.disconnect()
        except Exception:
            pass
        try:
            self.redis_client.set('jukebox:status', json.dumps({
                'state': 'stopped',
                'timestamp': time.time()
            }))
        except Exception:
            pass
        logger.info("Shutdown complete")

if __name__ == "__main__":
    player = JukeboxPlayer()
    player.run()