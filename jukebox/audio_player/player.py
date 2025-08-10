#!/usr/bin/env python3
"""
Music Player Controller for Jukebox System
Uses MPD (Music Player Daemon) for rock-solid audio playback
"""

import os
import sys
import time
import json
import logging
import threading
from pathlib import Path
from typing import Optional, Dict, List
import redis
import requests
from mpd import MPDClient, ConnectionError, CommandError

# Configure logging (fallback if /var/log is not writable)
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)
_formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
_handlers = [logging.StreamHandler()]
_log_file = os.environ.get('JUKEBOX_LOG_FILE', '/var/log/jukebox_player.log')
try:
    _fh = logging.FileHandler(_log_file)
except Exception:
    try:
        _fh = logging.FileHandler(str(Path.home() / 'jukebox_player.log'))
    except Exception:
        _fh = None
if _fh:
    _fh.setFormatter(_formatter)
    _handlers.append(_fh)
for _h in _handlers:
    _h.setFormatter(_formatter)
    logger.addHandler(_h)

class JukeboxPlayer:
    """Main jukebox player controller"""
    
    def __init__(self, config_path: str = None):
        self.config = self.load_config(config_path)
        self.redis_client = redis.Redis(
            host=self.config.get('redis_host', 'localhost'),
            port=self.config.get('redis_port', 6379),
            db=self.config.get('redis_db', 0)
        )
        self.mpd_client = None
        self.current_song = None
        self.is_playing = False
        self.shutdown_event = threading.Event()
        self.selection_lock = threading.Lock()
        # Desired player state: 'playing' | 'paused' | 'stopped'
        self.desired_state = self._load_desired_state()
        
        # Initialize MPD connection
        self.connect_mpd()
        
        # Start background threads
        self.start_background_threads()
    
    def load_config(self, config_path: str = None) -> Dict:
        """Load configuration from file or use defaults"""
        if config_path and os.path.exists(config_path):
            with open(config_path, 'r') as f:
                return json.load(f)
        
        # Default configuration
        return {
            'mpd_host': os.environ.get('MPD_HOST', 'localhost'),
            'mpd_port': int(os.environ.get('MPD_PORT', '6600')),
            'mpd_password': os.environ.get('MPD_PASSWORD') or None,
            'redis_host': os.environ.get('REDIS_HOST', 'localhost'),
            'redis_port': int(os.environ.get('REDIS_PORT', '6379')),
            'redis_db': int(os.environ.get('REDIS_DB', '0')),
            'jukebox_api_url': os.environ.get('JUKEBOX_API_URL', 'http://localhost:3001/api'),
            'cache_directory': '/var/lib/jukebox/cache',
            'crossfade_duration': 6,
            'prequeue_margin': 3,  # seconds before crossfade to request next
            'prequeue_enabled': False,
            'volume': 80,
            'retry_attempts': 3,
            'retry_delay': 5
        }
    
    def connect_mpd(self):
        """Connect to MPD daemon"""
        try:
            self.mpd_client = MPDClient()
            self.mpd_client.connect(
                self.config['mpd_host'],
                self.config['mpd_port']
            )
            
            if self.config.get('mpd_password'):
                self.mpd_client.password(self.config['mpd_password'])
            
            # Configure MPD settings
            self.mpd_client.crossfade(self.config['crossfade_duration'])
            self.mpd_client.setvol(self.config['volume'])
            # Ensure MPD does not loop old items; consume removes played items
            try:
                self.mpd_client.repeat(0)
                self.mpd_client.random(0)
                self.mpd_client.single(0)
                self.mpd_client.consume(1)
            except Exception:
                pass
            
            logger.info("Connected to MPD successfully")
            
        except (ConnectionError, CommandError) as e:
            logger.error(f"Failed to connect to MPD: {e}")
            raise
    
    def reconnect_mpd(self):
        """Reconnect to MPD if connection is lost"""
        try:
            self.mpd_client.disconnect()
        except:
            pass
        
        time.sleep(1)
        self.connect_mpd()

    def _load_desired_state(self) -> str:
        try:
            raw = self.redis_client.get('jukebox:desired_state')
            state = raw.decode('utf-8') if raw else 'playing'
            if state not in ('playing', 'paused', 'stopped'):
                state = 'playing'
            logger.info(f"Desired state: {state}")
            return state
        except Exception:
            return 'playing'

    def _save_desired_state(self):
        try:
            self.redis_client.set('jukebox:desired_state', self.desired_state)
        except Exception:
            pass
    
    def get_next_song(self) -> Optional[Dict]:
        """Ask Rails for the next song to play; Rails consumes queue and applies logic."""
        try:
            url = f"{self.config['jukebox_api_url']}/jukebox/player/next"
            resp = requests.get(url, timeout=5)
            if resp.status_code == 200:
                song_data = resp.json()
                logger.info(f"Next song: {song_data.get('title', 'Unknown')} (id={song_data.get('id')}) stream={song_data.get('stream_url')}")
                return song_data
            elif resp.status_code == 204:
                logger.info("No next song available")
                return None
            else:
                logger.error(f"Next song request failed: {resp.status_code}")
                return None
        except Exception as e:
            logger.error(f"Error requesting next song: {e}")
            return None
    
    def request_random_pool_refill(self):
        """Deprecated with next-song API; no-op."""
        return
    
    def check_system_status(self) -> Dict:
        """Check the current system status"""
        try:
            queue_length = self.redis_client.llen('jukebox:queue')
            random_pool_size = self.redis_client.llen('jukebox:random_pool')
            
            status = {
                'queue_length': queue_length,
                'random_pool_size': random_pool_size,
                'current_song': self.current_song,
                'is_playing': self.is_playing,
                'has_content': queue_length > 0 or random_pool_size > 0
            }
            
            # Log status for debugging
            if not status['has_content']:
                logger.warning(f"System status: Queue={queue_length}, Random Pool={random_pool_size} - No content available")
            
            return status
            
        except Exception as e:
            logger.error(f"Error checking system status: {e}")
            return {'error': str(e)}
    
    def ensure_song_cached(self, song_data: Dict) -> bool:
        """We always use stream_url (preferred) or local cached_path if exists."""
        return bool(song_data.get('stream_url') or (song_data.get('cached_path') and os.path.exists(song_data.get('cached_path'))))
    
    def download_song(self, song_data: Dict) -> bool:
        """Download song from archive to local cache"""
        try:
            song_id = song_data.get('id')
            download_url = f"{self.config['jukebox_api_url']}/songs/{song_id}/download"
            
            # Create cache directory
            cache_dir = Path(self.config['cache_directory'])
            cache_dir.mkdir(parents=True, exist_ok=True)
            
            # Download file
            response = requests.get(download_url, stream=True)
            response.raise_for_status()
            
            # Determine file extension from content type
            content_type = response.headers.get('content-type', 'application/octet-stream')
            if 'flac' in content_type:
                extension = '.flac'
            elif 'mpeg' in content_type or 'mp3' in content_type:
                extension = '.mp3'
            elif 'wav' in content_type:
                extension = '.wav'
            elif 'ogg' in content_type:
                extension = '.ogg'
            elif 'm4a' in content_type or 'aac' in content_type or 'mp4' in content_type:
                extension = '.m4a'
            else:
                extension = ''
            
            file_path = cache_dir / f"{song_id}{extension}"
            
            with open(file_path, 'wb') as f:
                for chunk in response.iter_content(chunk_size=8192):
                    f.write(chunk)
            
            # Update song data with cached path
            song_data['cached_path'] = str(file_path)
            
            # Notify Rails app that song is cached
            self.redis_client.set(f"jukebox:cached:{song_id}", json.dumps(song_data))
            
            logger.info(f"Successfully cached song {song_id}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to download song {song_id}: {e}")
            return False
    
    def play_song(self, song_data: Dict, force_play: bool = False):
        """Play a song using MPD (supports local path or HTTP URL). If force_play is True, clear and play immediately."""
        try:
            # Determine source: prefer cached local path, fallback to HTTP stream URL
            file_path = song_data.get('cached_path')
            stream_url = song_data.get('stream_url')
            source = None
            if file_path and os.path.exists(file_path):
                source = file_path
            elif stream_url:
                source = stream_url
            else:
                logger.error(f"No playable source for song {song_data.get('id')}")
                return False

            # If nothing queued, add and play; otherwise add only (for crossfade)
            status = self.mpd_client.status()
            playlist_length = int(status.get('playlistlength', '0')) if status else 0
            logger.info(f"MPD add source: {source}")
            if force_play:
                self.mpd_client.clear()
                self.mpd_client.add(source)
                self.mpd_client.play()
                logger.info("MPD play issued (force)")
            else:
                if playlist_length == 0:
                    self.mpd_client.clear()
                    self.mpd_client.add(source)
                    self.mpd_client.play()
                    logger.info("MPD play issued")
                else:
                    self.mpd_client.add(source)

            self.current_song = song_data
            self.is_playing = True

            # Notify Rails app about current song
            self.redis_client.set('jukebox:current_song', json.dumps(song_data))

            display_source = file_path if (file_path and os.path.exists(file_path)) else stream_url
            logger.info(f"Now playing: {song_data.get('title', 'Unknown')} -> {display_source}")
            return True
        except Exception as e:
            logger.error(f"Error playing song: {e}")
            return False

    def fetch_and_play_next(self, force_play: bool = True):
        """Fetch next song from Rails (triggers refill if needed) and play it, serialized to avoid races."""
        if not self.selection_lock.acquire(blocking=False):
            return
        try:
            if self.desired_state != 'playing':
                logger.info(f"Not fetching next; desired_state={self.desired_state}")
                return
            next_song = self.get_next_song()
            if next_song:
                self.play_song(next_song, force_play=force_play)
            else:
                logger.warning("No next song available to play")
        finally:
            self.selection_lock.release()
    
    def handle_mpd_events(self):
        """Handle MPD events and state changes"""
        try:
            status = self.mpd_client.status()
            if not status:
                return
            state = status.get('state')
            elapsed = float(status.get('elapsed', '0') or 0)
            duration = float(status.get('duration', '0') or 0)
            if not duration and status.get('time'):
                # sometimes time is like '12:180'
                try:
                    parts = status.get('time').split(':')
                    elapsed = float(parts[0])
                    duration = float(parts[1])
                except Exception:
                    pass
            remaining = max(0.0, duration - elapsed) if duration else 0.0
            playlist_length = int(status.get('playlistlength', '0') or 0)

            # If stopped, fetch next immediately
            if state == 'stop':
                self.is_playing = False
                self.current_song = None
                if self.desired_state == 'playing':
                    self.fetch_and_play_next(force_play=True)
                return

            # Pre-queue next track when approaching crossfade threshold
            threshold = float(self.config.get('crossfade_duration', 6)) + float(self.config.get('prequeue_margin', 3))
            if self.desired_state == 'playing' and state == 'play' and playlist_length <= 1 and remaining and remaining <= threshold:
                self.fetch_and_play_next(force_play=False)
            
        except Exception as e:
            logger.error(f"Error handling MPD events: {e}")
            self.reconnect_mpd()
    
    def pause_player(self):
        """Pause the player when no content is available"""
        try:
            # Pause MPD
            self.mpd_client.pause()
            self.is_playing = False
            
            # Update status to paused
            self.redis_client.set('jukebox:status', json.dumps({
                'state': 'paused',
                'reason': 'no_content',
                'message': 'No songs available in queue or random pool',
                'timestamp': time.time()
            }))
            
            logger.info("Player paused - waiting for user interaction")
            
        except Exception as e:
            logger.error(f"Error pausing player: {e}")
    
    def resume_player(self):
        """Resume the player when content becomes available"""
        try:
            # Check if we have content
            system_status = self.check_system_status()
            if system_status.get('has_content', False):
                # Update status to playing
                self.redis_client.set('jukebox:status', json.dumps({
                    'state': 'playing',
                    'timestamp': time.time()
                }))
                
                logger.info("Resuming player - content available")
                return True
            else:
                logger.info("Cannot resume - no content available")
                return False
                
        except Exception as e:
            logger.error(f"Error resuming player: {e}")
            return False
    
    def handle_redis_commands(self):
        """Handle commands from Redis queue"""
        try:
            command_data = self.redis_client.blpop('jukebox:commands', timeout=1)
            if not command_data:
                return
            
            command = json.loads(command_data[1])
            action = command.get('action')
            
            logger.info(f"Received command: {action}")
            
            if action == 'play':
                # Check if we have content before playing
                self.desired_state = 'playing'
                self._save_desired_state()
                self.fetch_and_play_next(force_play=True)
                
            elif action == 'pause':
                self.desired_state = 'paused'
                self._save_desired_state()
                self.mpd_client.pause(1)
                self.is_playing = False
                
            elif action == 'stop':
                self.desired_state = 'stopped'
                self._save_desired_state()
                self.mpd_client.stop()
                self.is_playing = False
                
            elif action == 'next':
                # Consume the next song from Rails (triggers refill if needed) and play it immediately
                try:
                    self.mpd_client.stop()
                except Exception:
                    pass
                if self.desired_state == 'playing':
                    self.fetch_and_play_next(force_play=True)
                else:
                    logger.info(f"Skip ignored; desired_state={self.desired_state}")
                
            elif action == 'previous':
                self.mpd_client.previous()
                
            elif action == 'volume':
                volume = command.get('volume', 80)
                self.mpd_client.setvol(volume)
                
            elif action == 'crossfade':
                duration = command.get('duration', 3)
                self.mpd_client.crossfade(duration)
                
            elif action == 'shutdown':
                self.shutdown_event.set()
                
        except Exception as e:
            logger.error(f"Error handling Redis commands: {e}")
    
    def start_background_threads(self):
        """Start background monitoring threads"""
        def mpd_monitor():
            while not self.shutdown_event.is_set():
                try:
                    self.handle_mpd_events()
                    time.sleep(1)
                except Exception as e:
                    logger.error(f"MPD monitor error: {e}")
                    time.sleep(5)
        
        def redis_monitor():
            while not self.shutdown_event.is_set():
                try:
                    self.handle_redis_commands()
                except Exception as e:
                    logger.error(f"Redis monitor error: {e}")
                    time.sleep(1)
        
        # Start threads
        threading.Thread(target=mpd_monitor, daemon=True).start()
        threading.Thread(target=redis_monitor, daemon=True).start()
    
    def run(self):
        """Main run loop"""
        logger.info("Starting Jukebox Player")
        logger.info(f"Using API base: {self.config.get('jukebox_api_url')}")
        
        # Initialize system status
        self.redis_client.set('jukebox:status', json.dumps({
            'state': 'starting',
            'timestamp': time.time()
        }))
        
        try:
            # Kick off playback if nothing is playing
            try:
                status = self.mpd_client.status()
                if self.desired_state == 'playing' and (not status or status.get('state') in (None, 'stop', 'paused')):
                    self.fetch_and_play_next(force_play=True)
            except Exception as e:
                logger.warning(f"Startup check failed: {e}")
            while not self.shutdown_event.is_set():
                # Light idle; MPD monitors handle prequeue/advance
                time.sleep(1)
                
        except KeyboardInterrupt:
            logger.info("Shutdown requested")
        except Exception as e:
            logger.error(f"Unexpected error: {e}")
        finally:
            self.shutdown()
    
    def shutdown(self):
        """Clean shutdown"""
        logger.info("Shutting down Jukebox Player")
        self.shutdown_event.set()
        
        try:
            if self.mpd_client:
                self.mpd_client.stop()
                self.mpd_client.disconnect()
        except:
            pass
        
        logger.info("Shutdown complete")

if __name__ == "__main__":
    config_path = sys.argv[1] if len(sys.argv) > 1 else None
    player = JukeboxPlayer(config_path)
    player.run() 