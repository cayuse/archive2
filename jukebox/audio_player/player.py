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
        """Initialize player"""
        self.config = self.load_config()
        self.redis_client = redis.Redis(
            host=self.config['redis_host'],
            port=self.config['redis_port'],
            db=self.config['redis_db'],
            decode_responses=False
        )
        self.mpd_client = None
        self.current_song = None
        self.is_playing = False
        self.desired_state = 'stopped'
        self.last_skip_time = 0  # Track when skip was last executed
        self.skip_cooldown = 2.0  # Don't pre-queue for 2 seconds after skip
        
        # Load desired state from Redis
        self.desired_state = self._load_desired_state()
        
        # Test Rails connection at startup
        self.test_rails_connection()
        
        # Connect to MPD
        self.connect_mpd()

    def load_config(self) -> Dict:
        """Load configuration from env vars"""
        return {
            'redis_host': os.getenv('REDIS_HOST', 'redis'),
            'redis_port': int(os.getenv('REDIS_PORT', '6379')),
            'redis_db': int(os.getenv('REDIS_DB', '1')),
            'jukebox_api_url': 'http://host.docker.internal:3001/api',  # Use host.docker.internal to reach host machine
            'crossfade_duration': 6,
            'prequeue_margin': 3,  # Add next song when 3 seconds + crossfade remaining
            'volume': 80,
            'retry_attempts': 3,
            'retry_delay': 1
        }

    def test_rails_connection(self):
        """Test if we can connect to the Rails API"""
        try:
            test_url = f"{self.config['jukebox_api_url']}/jukebox/health"
            logger.info(f"Testing Rails API connection to: {test_url}")
            
            response = requests.get(test_url, timeout=5)
            logger.info(f"Rails API health check response: {response.status_code}")
            
            if response.status_code == 200:
                logger.info("Rails API connection successful")
                return True
            else:
                logger.warning(f"Rails API health check failed: {response.status_code}")
                return False
                
        except Exception as e:
            logger.error(f"Rails API connection test failed: {e}")
            return False

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
                self.mpd_client.repeat(0)      # NO REPEAT
                self.mpd_client.random(0)      # NO RANDOM
                self.mpd_client.single(0)      # CONTINUE TO NEXT SONG
                self.mpd_client.consume(1)     # REMOVE SONG AFTER PLAYING
                logger.info("MPD configured: no repeat, no random, continue to next, consume enabled")
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
        """Get next song from Rails API"""
        import traceback
        
        # Get call stack to see where this is being called from
        caller = traceback.extract_stack()[-2] if len(traceback.extract_stack()) > 1 else None
        caller_info = f"{caller.filename}:{caller.lineno}" if caller else "unknown"
        
        logger.info(f"=== GET_NEXT_SONG CALLED from {caller_info} ===")
        
        for attempt in range(1, self.config['retry_attempts'] + 1):
            try:
                logger.info(f"Next song attempt {attempt}/{self.config['retry_attempts']}")
                response = requests.get(f"{self.config['jukebox_api_url']}/jukebox/player/next", timeout=5)
                logger.info(f"Response status: {response.status_code}")
                
                if response.status_code == 200:
                    song_data = response.json()
                    logger.info(f"Got next song: {song_data.get('title', 'Unknown')} (ID: {song_data.get('id', 'Unknown')})")
                    return song_data
                else:
                    logger.warning(f"Next song attempt {attempt} failed: HTTP {response.status_code}")
                    
            except Exception as e:
                logger.warning(f"Next song attempt {attempt} failed: {e}")
                
            if attempt < self.config['retry_attempts']:
                logger.info(f"Waiting {self.config['retry_delay']} seconds before retry")
                time.sleep(self.config['retry_delay'])
                
        logger.error("No next song available for play")
        return None

    def play_song(self, song_data: Dict, force_play: bool = False):
        """Play song via MPD using stream_url - handles queueing properly"""
        try:
            logger.info(f"=== PLAY_SONG START ===")
            logger.info(f"Song data received: {song_data}")
            
            stream_url = song_data.get('stream_url')
            logger.info(f"Extracted stream_url: {stream_url}")
            
            if not stream_url:
                logger.error(f"No stream_url for song {song_data.get('id')}")
                logger.error(f"Full song_data: {song_data}")
                return False
                
            # Get MPD status to check playlist
            try:
                logger.info("Getting MPD status before operations...")
                status = self.mpd_client.status()
                logger.info(f"MPD status before operations: {status}")
                playlist_length = int(status.get('playlistlength', '0')) if status else 0
                actual_state = status.get('state', 'stop')
                logger.info(f"Current playlist length: {playlist_length}")
                logger.info(f"Current MPD state: {actual_state}")
            except Exception as e:
                logger.error(f"Error getting MPD status before operations: {e}")
                playlist_length = 0
                actual_state = 'stop'
                
            if force_play or playlist_length == 0:
                # Clear playlist and start fresh
                logger.info(f"FORCE_PLAY BRANCH: force_play={force_play}, playlist_length={playlist_length}")
                logger.info(f"Clearing playlist and adding new song (force_play={force_play}, playlist_length={playlist_length})")
                try:
                    self.mpd_client.clear()
                    logger.info("Playlist cleared successfully")
                except Exception as e:
                    logger.error(f"Error clearing playlist: {e}")
                    return False
                    
                try:
                    logger.info(f"Adding stream URL to MPD: {stream_url}")
                    self.mpd_client.add(stream_url)
                    logger.info("Stream URL added to MPD successfully")
                except Exception as e:
                    logger.error(f"Error adding stream URL to MPD: {e}")
                    logger.error(f"Stream URL that failed: {stream_url}")
                    return False
                    
                try:
                    logger.info("Sending play command to MPD")
                    self.mpd_client.play()
                    logger.info("Play command sent successfully")
                except Exception as e:
                    logger.error(f"Error sending play command to MPD: {e}")
                    return False
                    
                logger.info(f"Playing {song_data.get('title', 'Unknown')} (force={force_play})")
            else:
                # Only add to playlist if we actually need more songs
                logger.info(f"ADD_TO_PLAYLIST BRANCH: force_play={force_play}, playlist_length={playlist_length}")
                # Don't add if we already have enough songs queued
                if playlist_length < 2:  # Keep 1-2 songs in queue max
                    try:
                        logger.info(f"Adding song to existing playlist: {stream_url}")
                        self.mpd_client.add(stream_url)
                        logger.info(f"Song queued successfully: {song_data.get('title', 'Unknown')}")
                        
                        # If we're not currently playing, start playback
                        if actual_state != 'play':
                            logger.info("Starting playback of queued song")
                            self.mpd_client.play()
                            logger.info("Playback started for queued song")
                            
                    except Exception as e:
                        logger.error(f"Error adding song to playlist: {e}")
                        return False
                else:
                    logger.info(f"Playlist already has {playlist_length} songs, skipping pre-queue")
                    return True  # Success - we didn't need to add anything
                    
            # Log MPD status after operations
            try:
                logger.info("Getting MPD status after operations...")
                new_status = self.mpd_client.status()
                logger.info(f"MPD status after operations: {new_status}")
                
                # Check if song is actually playing
                current_song = self.mpd_client.currentsong()
                logger.info(f"Current song info: {current_song}")
                
            except Exception as e:
                logger.error(f"Error getting MPD status after operations: {e}")
                
            self.current_song = song_data
            self.is_playing = True
            
            try:
                logger.info("Saving current song to Redis...")
                self.redis_client.set('jukebox:current_song', json.dumps(song_data))
                logger.info("Current song saved to Redis successfully")
            except Exception as e:
                logger.error(f"Error saving current song to Redis: {e}")
                
            logger.info(f"=== PLAY_SONG SUCCESS ===")
            return True
            
        except Exception as e:
            logger.error(f"=== PLAY_SONG ERROR ===")
            logger.error(f"Error playing song: {e}")
            logger.error(f"Exception type: {type(e).__name__}")
            logger.error(f"Exception details: {str(e)}")
            logger.error(f"Song data that caused error: {song_data}")
            return False

    def collapse_commands(self, commands: list) -> Dict:
        """Collapse command queue into action plan"""
        action_plan = {}
        state_priority = {'play': 1, 'pause': 2, 'stop': 3, 'next': 4}  # Added 'next' with highest priority
        for cmd in commands:
            try:
                cmd_data = json.loads(cmd.decode('utf-8') if isinstance(cmd, bytes) else cmd)
                action = cmd_data.get('action')
                if action in ('play', 'pause', 'stop', 'next'):  # Added 'next' to state actions
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
            logger.info(f"=== EXECUTE ACTION PLAN START ===")
            logger.info(f"Action plan: {action_plan}")
            
            # State commands
            if 'state_action' in action_plan:
                action = action_plan['state_action']
                logger.info(f"Executing state action: {action}")
                
                if action == 'stop':
                    logger.info("Executing STOP command")
                    self.desired_state = 'stopped'
                    self.mpd_client.stop()
                    self.is_playing = False
                    self.current_song = None
                    logger.info("STOP command executed successfully")
                    
                elif action == 'pause':
                    logger.info("Executing PAUSE command")
                    status = self.mpd_client.status()
                    logger.info(f"MPD status before pause: {status}")
                    
                    if status.get('state') in ('stop', 'pause'):
                        # Pause means play if not playing - but don't get new songs
                        logger.info("MPD is stopped/paused, resuming existing playback")
                        self.desired_state = 'playing'
                        # Don't call get_next_song() here - just resume what's already queued
                        if status.get('playlistlength', '0') == '0':
                            # Only get new song if playlist is completely empty
                            logger.info("Playlist empty, getting next song")
                            next_song = self.get_next_song()
                            if next_song:
                                logger.info(f"Got next song for pause->play: {next_song.get('title')}")
                                if not self.play_song(next_song, force_play=True):
                                    logger.error("Failed to play next song after pause->play")
                                    self.desired_state = 'stopped'
                                    self.mpd_client.stop()
                            else:
                                logger.error("No next song available for pause->play")
                                self.desired_state = 'stopped'
                                self.mpd_client.stop()
                        else:
                            # Resume existing playlist
                            logger.info("Resuming existing playlist")
                            self.mpd_client.play()
                    else:
                        logger.info("MPD is playing, pausing playback")
                        self.desired_state = 'paused'
                        self.mpd_client.pause(1)
                        self.is_playing = False
                    logger.info("PAUSE command executed successfully")
                    
                elif action == 'play':
                    logger.info("Executing PLAY command")
                    self.desired_state = 'playing'
                    status = self.mpd_client.status()
                    logger.info(f"MPD status before play: {status}")
                    
                    if status.get('state') == 'pause':
                        logger.info("MPD is paused, resuming playback")
                        self.mpd_client.pause(0)
                        self.is_playing = True
                    elif status.get('state') != 'play':
                        logger.info("MPD is not playing, attempting to play next song")
                        next_song = self.get_next_song()
                        if next_song:
                            logger.info(f"Got next song for play: {next_song.get('title')}")
                            if not self.play_song(next_song, force_play=True):
                                logger.error("Failed to play next song")
                                self.desired_state = 'stopped'
                                self.mpd_client.stop()
                        else:
                            logger.error("No next song available for play")
                            self.desired_state = 'stopped'
                            self.mpd_client.stop()
                    else:
                        logger.info("MPD is already playing")
                    logger.info("PLAY command executed successfully")
                    
                elif action == 'next':
                    logger.info("Executing NEXT command")
                    
                    # Set skip timestamp to prevent immediate pre-queuing
                    self.last_skip_time = time.time()
                    logger.info(f"Skip executed at {self.last_skip_time}, pre-queuing disabled for {self.skip_cooldown}s")
                    
                    # Immediately stop current playback (kills crossfade if happening)
                    try:
                        logger.info("Stopping current playback for skip")
                        self.mpd_client.stop()
                        logger.info("Current playback stopped successfully")
                        
                        # Small delay to ensure MPD has fully stopped
                        time.sleep(0.1)
                        
                    except Exception as e:
                        logger.error(f"Error stopping current playback: {e}")
                    
                    # Get and play next song
                    next_song = self.get_next_song()
                    if next_song:
                        logger.info(f"Got next song for skip: {next_song.get('title')}")
                        if not self.play_song(next_song, force_play=True):
                            logger.error("Failed to play next song after skip")
                            self.desired_state = 'stopped'
                            self.mpd_client.stop()
                        else:
                            logger.info("Next song started successfully after skip")
                            self.desired_state = 'playing'  # Ensure we're in playing state
                    else:
                        logger.error("No next song available for skip")
                        self.desired_state = 'stopped'
                        self.mpd_client.stop()
                    logger.info("NEXT command executed successfully")
                    
                self._save_desired_state()

            # Volume commands (last wins)
            if 'volume_action' in action_plan:
                cmd = action_plan['volume_action']
                action = cmd.get('action')
                logger.info(f"Executing volume action: {action}")
                
                try:
                    current_volume = int(self.mpd_client.status().get('volume', '0') or 0)
                    logger.info(f"Current MPD volume: {current_volume}")
                    
                    if action == 'set_volume':
                        volume = max(0, min(100, int(cmd.get('value', current_volume))))
                        logger.info(f"Setting volume to: {volume}")
                    elif action == 'volume_up':
                        volume = min(100, current_volume + 10)
                        logger.info(f"Increasing volume from {current_volume} to {volume}")
                    elif action == 'volume_down':
                        volume = max(0, current_volume - 10)
                        logger.info(f"Decreasing volume from {current_volume} to {volume}")
                        
                    self.mpd_client.setvol(volume)
                    self.redis_client.set('jukebox:current_volume', volume)
                    logger.info(f"Volume set to {volume} successfully")
                    
                except Exception as e:
                    logger.error(f"Error setting volume: {e}")

            # Crossfade
            if 'crossfade_action' in action_plan:
                duration = int(max(0, min(100, action_plan['crossfade_action'].get('value', 0))))
                logger.info(f"Setting crossfade to {duration} seconds")
                try:
                    self.mpd_client.crossfade(duration)
                    logger.info(f"Crossfade set to {duration}s successfully")
                except Exception as e:
                    logger.error(f"Error setting crossfade: {e}")
                    
            logger.info(f"=== EXECUTE ACTION PLAN COMPLETED ===")
            
        except Exception as e:
            logger.error(f"=== EXECUTE ACTION PLAN ERROR ===")
            logger.error(f"Error executing action plan: {e}")
            logger.error(f"Exception type: {type(e).__name__}")
            logger.error(f"Exception details: {str(e)}")
            logger.error(f"Action plan that caused error: {action_plan}")

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
                    # Don't automatically get next song here - let the pre-queuing logic handle it
                    # Just ensure MPD is playing if we have songs in the playlist
                    if playlist_length > 0:
                        logger.info("Resuming playback from existing playlist")
                        self.mpd_client.play()
                    else:
                        logger.info("No songs in playlist, getting next song")
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

            # Extremely late next-song fetching - only when song is almost done
            threshold = self.config['crossfade_duration'] + self.config['prequeue_margin']  # 6 + 3 = 9 seconds
            
            # Check if we're in skip cooldown period
            time_since_skip = time.time() - self.last_skip_time
            in_skip_cooldown = time_since_skip < self.skip_cooldown
            
            if (self.desired_state == 'playing' and 
                actual_state == 'play' and 
                remaining <= threshold and
                not in_skip_cooldown):  # Don't pre-queue during skip cooldown
                
                logger.info(f"Song ending soon (remaining: {remaining:.1f}s, threshold: {threshold}s), checking if we need next song")
                logger.info(f"Skip cooldown: {time_since_skip:.1f}s since last skip (cooldown: {self.skip_cooldown}s)")
                
                # Only fetch next song if playlist is actually running low
                # We want to maintain exactly 1-2 songs in the queue
                if playlist_length <= 1:
                    logger.info("Playlist running low, fetching next song from Rails")
                    next_song = self.get_next_song()
                    if next_song:
                        logger.info(f"Pre-queuing next song: {next_song.get('title')}")
                        if not self.play_song(next_song, force_play=False):
                            logger.warning("Failed to pre-queue next song, will try again")
                    else:
                        logger.info("No next song available for pre-queue")
                else:
                    logger.info(f"Playlist has {playlist_length} songs, no need to fetch next yet")
            elif in_skip_cooldown:
                logger.debug(f"In skip cooldown ({time_since_skip:.1f}s remaining), skipping pre-queue check")
                    
            # Also handle completely empty playlist
            elif (self.desired_state == 'playing' and 
                  actual_state == 'play' and 
                  playlist_length == 0 and
                  not in_skip_cooldown):  # Don't auto-fetch during skip cooldown
                
                logger.info("Playlist empty while playing, fetching next song")
                if not self.play_song(self.get_next_song(), force_play=True):
                    logger.error("No next song available, stopping playback")
                    self.desired_state = 'stopped'
                    self.mpd_client.stop()
                    error_message = 'No next song available'
                    
            # NO AUTO-QUEUING - Rails app is the only source of truth for next songs
            # The Python player only plays what it's explicitly told to play
            
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
        logger.info(f"MPD connection: host.docker.internal:6600")
        logger.info(f"Redis connection: {self.config.get('redis_host')}:{self.config.get('redis_port')}")
        
        try:
            self.redis_client.set('jukebox:status', json.dumps({
                'state': 'starting',
                'timestamp': time.time()
            }))
            
            while True:
                start_time = time.time()
                logger.debug(f"=== MAIN LOOP ITERATION ===")
                
                # Step 1: Pull and collapse commands
                try:
                    commands = self.redis_client.lrange('jukebox:commands', 0, -1)
                    if commands:
                        logger.info(f"Processing {len(commands)} commands from Redis queue")
                        logger.info(f"Commands: {commands}")
                        self.redis_client.delete('jukebox:commands')
                        action_plan = self.collapse_commands(commands)
                        logger.info(f"Collapsed action plan: {action_plan}")
                        
                        # Step 2: Execute action plan
                        logger.info("Executing action plan...")
                        self.execute_action_plan(action_plan)
                        logger.info("Action plan execution completed")
                    else:
                        logger.debug("No commands in Redis queue")
                        
                except Exception as e:
                    logger.error(f"Error processing commands: {e}")
                    
                # Step 3: Poll and update status
                logger.debug("Polling MPD and updating status...")
                self.update_status()
                
                # Log current playback status for debugging
                try:
                    current_status = self.mpd_client.status()
                    if current_status.get('state') == 'play':
                        elapsed = float(current_status.get('elapsed', '0') or 0)
                        duration = float(current_status.get('duration', '0') or 0)
                        remaining = max(0.0, duration - elapsed) if duration else 0.0
                        playlist_length = int(current_status.get('playlistlength', '0') or 0)
                        threshold = self.config['crossfade_duration'] + self.config['prequeue_margin']
                        
                        logger.debug(f"Playback status - Elapsed: {elapsed:.1f}s, Duration: {duration:.1f}s, Remaining: {remaining:.1f}s, Playlist: {playlist_length} songs, Next fetch in: {max(0, remaining - threshold):.1f}s")
                        
                        # Warn if we're getting close to the end with no more songs
                        if remaining <= threshold and playlist_length <= 1:
                            logger.info(f"⚠️ Song ending soon (remaining: {remaining:.1f}s) with only {playlist_length} song(s) in playlist")
                            
                except Exception as e:
                    logger.debug(f"Could not get current playback status: {e}")
                
                # Step 4: Sleep to ~1s
                elapsed = time.time() - start_time
                sleep_time = max(0, 1 - elapsed)
                logger.debug(f"Loop iteration took {elapsed:.3f}s, sleeping for {sleep_time:.3f}s")
                time.sleep(sleep_time)
                
        except KeyboardInterrupt:
            logger.info("Shutdown requested")
        except Exception as e:
            logger.error(f"Unexpected error in main loop: {e}")
            logger.error(f"Exception type: {type(e).__name__}")
            logger.error(f"Exception details: {str(e)}")
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