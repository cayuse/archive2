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

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/jukebox_player.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

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
            'mpd_host': 'localhost',
            'mpd_port': 6600,
            'mpd_password': None,
            'redis_host': 'localhost',
            'redis_port': 6379,
            'redis_db': 0,
            'jukebox_api_url': 'http://localhost:3001/api',
            'cache_directory': '/var/lib/jukebox/cache',
            'crossfade_duration': 3,
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
    
    def get_next_song(self) -> Optional[Dict]:
        """Get the next song to play from queue or random pool"""
        try:
            # Check user queue first (FIFO)
            queue_data = self.redis_client.lpop('jukebox:queue')
            if queue_data:
                song_data = json.loads(queue_data)
                logger.info(f"Playing queued song: {song_data.get('title', 'Unknown')}")
                return song_data
            
            # Fall back to random song from active playlists
            random_song = self.redis_client.rpop('jukebox:random_pool')
            if random_song:
                song_data = json.loads(random_song)
                logger.info(f"Playing random song: {song_data.get('title', 'Unknown')}")
                return song_data
            
            # No songs available - try to refill random pool
            logger.warning("No songs available in queue or random pool")
            self.request_random_pool_refill()
            
            return None
            
        except Exception as e:
            logger.error(f"Error getting next song: {e}")
            return None
    
    def request_random_pool_refill(self):
        """Request the Rails app to refill the random pool"""
        try:
            # Send a refill request to Redis
            self.redis_client.rpush('jukebox:requests', json.dumps({
                'action': 'refill_random_pool',
                'timestamp': time.time()
            }))
            logger.info("Requested random pool refill")
        except Exception as e:
            logger.error(f"Failed to request random pool refill: {e}")
    
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
        """Ensure song is cached locally before playing"""
        song_id = song_data.get('id')
        file_path = song_data.get('cached_path')
        
        if not file_path or not os.path.exists(file_path):
            logger.warning(f"Song {song_id} not cached, attempting to download")
            return self.download_song(song_data)
        
        return True
    
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
            
            # Determine file extension
            content_type = response.headers.get('content-type', 'audio/mpeg')
            extension = '.mp3' if 'mpeg' in content_type else '.wav'
            
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
    
    def play_song(self, song_data: Dict):
        """Play a song using MPD"""
        try:
            if not self.ensure_song_cached(song_data):
                logger.error(f"Cannot play song {song_data.get('id')} - not cached")
                return False
            
            file_path = song_data.get('cached_path')
            
            # Clear current playlist and add new song
            self.mpd_client.clear()
            self.mpd_client.add(file_path)
            self.mpd_client.play()
            
            self.current_song = song_data
            self.is_playing = True
            
            # Notify Rails app about current song
            self.redis_client.set('jukebox:current_song', json.dumps(song_data))
            
            logger.info(f"Now playing: {song_data.get('title', 'Unknown')}")
            return True
            
        except Exception as e:
            logger.error(f"Error playing song: {e}")
            return False
    
    def handle_mpd_events(self):
        """Handle MPD events and state changes"""
        try:
            status = self.mpd_client.status()
            
            if status.get('state') == 'stop' and self.is_playing:
                # Song finished, get next song
                logger.info("Song finished, getting next song")
                self.is_playing = False
                self.current_song = None
                
                next_song = self.get_next_song()
                if next_song:
                    self.play_song(next_song)
                else:
                    # No more songs available - pause the player
                    logger.info("No more songs available - pausing player")
                    self.pause_player()
            
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
                if self.resume_player():
                    self.mpd_client.play()
                    self.is_playing = True
                else:
                    logger.warning("Cannot play - no content available")
                
            elif action == 'pause':
                self.mpd_client.pause()
                self.is_playing = False
                
            elif action == 'stop':
                self.mpd_client.stop()
                self.is_playing = False
                
            elif action == 'next':
                self.mpd_client.next()
                
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
        
        # Initialize system status
        self.redis_client.set('jukebox:status', json.dumps({
            'state': 'starting',
            'timestamp': time.time()
        }))
        
        try:
            while not self.shutdown_event.is_set():
                # Check if we need to start playing
                if not self.is_playing and not self.current_song:
                    next_song = self.get_next_song()
                    if next_song:
                        self.play_song(next_song)
                        # Update status to playing
                        self.redis_client.set('jukebox:status', json.dumps({
                            'state': 'playing',
                            'timestamp': time.time()
                        }))
                    else:
                        # No content available - pause and wait for user interaction
                        logger.info("No content available - pausing player")
                        self.pause_player()
                        # Wait for user interaction (check every 10 seconds)
                        time.sleep(10)
                else:
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