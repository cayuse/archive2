#!/usr/bin/env python3
"""
Music Player Controller for Jukebox System
Uses pygame for audio playback via stream URLs with crossfade, Redis for state/commands, HTTP to Rails for next song
Supports mp3, ogg, flac, m4a via ffmpeg transcoding
Single-threaded loop: process commands, poll status, report to Redis every ~1s
"""

import os
import time
import json
import logging
from pathlib import Path
from typing import Dict, Optional
import redis
import requests
import pygame
from io import BytesIO
import subprocess
import tempfile

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
    """Jukebox player controller using pygame and Redis"""

    def __init__(self):
        self.config = self.load_config()
        self.volume = self.config['volume']
        self._initialize_pygame()
        self.redis_client = redis.Redis(
            host=self.config['redis_host'],
            port=self.config['redis_port'],
            db=self.config['redis_db']
        )
        self.desired_state = self._load_desired_state()
        self.current_song = None
        self.is_playing = False
        self.crossfade_duration = self.config['crossfade_duration'] * 1000  # ms
        self.prequeue_margin = self.config['prequeue_margin']  # seconds
        self.music = pygame.mixer.music
        self.next_channel = pygame.mixer.Channel(1)
        self.next_song = None
        self.next_song_data = None  # Store the song metadata separately
        self.next_song_preloaded = False
        self.start_time = 0
        self.duration = 0
        self.paused_time = 0
        self.crossfade_start = 0

    def _initialize_pygame(self):
        """Initialize pygame mixer"""
        try:
            pygame.mixer.init(frequency=44100, size=-16, channels=2, buffer=512)
            pygame.mixer.music.set_volume(self.volume / 100.0)
            logger.info(f"Pygame mixer initialized - frequency: 44100, size: 16-bit, channels: 2, buffer: 512")
            logger.info(f"Initial volume set to: {self.volume}%")
            
            # Test if we can access the audio device
            test_sound = pygame.mixer.Sound(bytes([0] * 1024))  # Create a silent test sound
            logger.info("Audio device test successful - pygame can access audio hardware")
            
            # Test if we can actually play audio
            try:
                test_sound.play()
                time.sleep(0.1)
                test_sound.stop()
                logger.info("Audio playback test successful - audio device is working")
            except Exception as e:
                logger.warning(f"Audio playback test failed: {e} - audio device may have issues")
            
        except Exception as e:
            logger.error(f"Failed to initialize pygame mixer: {e}")
            raise

    def load_config(self) -> Dict:
        """Load configuration from env vars"""
        return {
            'redis_host': os.getenv('REDIS_HOST', 'localhost'),
            'redis_port': int(os.getenv('REDIS_PORT', '6379')),
            'redis_db': int(os.getenv('REDIS_DB', '1')),
            'jukebox_api_url': os.getenv('JUKEBOX_API_URL', 'http://localhost:3001/api'),
            'crossfade_duration': 6,  # seconds
            'prequeue_margin': 3,  # seconds - add next song when this much time remaining
            'volume': 80,
            'retry_attempts': 3,
            'retry_delay': 1
        }

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

    def _transcode_to_wav(self, stream_url: str) -> BytesIO:
        """Transcode stream to WAV using ffmpeg"""
        try:
            # Check if ffmpeg is available
            try:
                subprocess.run(['ffmpeg', '-version'], capture_output=True, check=True)
                logger.info("FFmpeg is available on the system")
            except (subprocess.CalledProcessError, FileNotFoundError):
                logger.error("FFmpeg is not available on the system - transcoding will fail")
                raise RuntimeError("FFmpeg not found - please install ffmpeg")
            
            logger.info(f"Starting ffmpeg transcoding of {stream_url}")
            with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as temp_file:
                # Use ffmpeg to transcode to WAV with specific audio settings
                process = subprocess.run([
                    'ffmpeg', '-y',  # Overwrite output file
                    '-i', stream_url,  # Input file
                    '-f', 'wav',  # Output format
                    '-acodec', 'pcm_s16le',  # 16-bit PCM
                    '-ar', '44100',  # 44.1kHz sample rate
                    '-ac', '2',  # Stereo
                    '-loglevel', 'error',  # Only show errors
                    temp_file.name
                ], capture_output=True, text=True, check=True)
                
                logger.info(f"FFmpeg transcoding completed successfully")
                
                # Read the transcoded file
                with open(temp_file.name, 'rb') as f:
                    wav_data = f.read()
                    logger.info(f"Transcoded WAV file size: {len(wav_data)} bytes")
                    return BytesIO(wav_data)
                    
        except subprocess.CalledProcessError as e:
            logger.error(f"FFmpeg transcoding failed: {e.stderr}")
            raise
        except Exception as e:
            logger.error(f"Unexpected error during transcoding: {e}")
            raise
        finally:
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)

    def play_song(self, song_data: Dict, force_play: bool = False):
        """Play song using pygame with stream_url, transcode if needed"""
        try:
            stream_url = song_data.get('stream_url')
            if not stream_url:
                logger.error(f"No stream_url for song {song_data.get('id')}")
                return False
            
            logger.info(f"Attempting to play from stream URL: {stream_url}")
            
            try:
                response = requests.get(stream_url, stream=True)
                if response.status_code != 200:
                    logger.error(f"Stream request failed: {response.status_code}")
                    return False
                audio_data = BytesIO(response.content)
                logger.info(f"Downloaded {len(response.content)} bytes of audio data")
                
                # Check if the audio data is valid
                if len(response.content) < 1024:  # Less than 1KB is probably not a valid audio file
                    logger.error(f"Audio file too small ({len(response.content)} bytes) - likely not a valid audio file")
                    return False
                
                # Check if the file has valid audio headers
                content = response.content
                if len(content) >= 4:
                    # Check for common audio file signatures
                    if content[:4] == b'fLaC':  # FLAC
                        logger.info("Detected FLAC file signature")
                    elif content[:4] == b'ID3':  # MP3
                        logger.info("Detected MP3 file signature")
                    elif content[:4] == b'RIFF':  # WAV
                        logger.info("Detected WAV file signature")
                    elif content[:4] == b'OggS':  # OGG
                        logger.info("Detected OGG file signature")
                    else:
                        logger.warning(f"Unknown audio file format - first 4 bytes: {content[:4]}")
                
                # Check if we need to transcode (pygame doesn't support FLAC well)
                content_type = response.headers.get('content-type', '')
                filename = stream_url.split('/')[-1] if '/' in stream_url else ''
                needs_transcoding = (
                    'flac' in content_type.lower() or 
                    'flac' in filename.lower() or
                    'audio/flac' in content_type.lower() or
                    'audio/ogg' in content_type.lower() or
                    'audio/x-m4a' in content_type.lower()
                )
                
                if needs_transcoding:
                    logger.info(f"Detected unsupported audio format ({content_type}), using ffmpeg transcoding")
                    raise pygame.error(f"Unsupported format detected ({content_type}) - forcing ffmpeg transcoding")
                
                if force_play or not self.is_playing:
                    logger.info(f"Loading audio data into pygame mixer")
                    logger.info(f"Audio data size: {len(audio_data.getvalue())} bytes")
                    
                    # Test if pygame can load this audio data
                    try:
                        test_sound = pygame.mixer.Sound(audio_data)
                        logger.info("Pygame successfully loaded audio data")
                        audio_data.seek(0)  # Reset position for music.load()
                    except pygame.error as e:
                        logger.warning(f"Pygame cannot load audio data directly: {e}")
                        logger.info("Falling back to ffmpeg transcoding")
                        raise pygame.error("Audio format not supported by pygame")
                    
                    self.music.load(audio_data)
                    logger.info(f"Starting pygame playback")
                    self.music.play()
                    
                    # Verify pygame is actually playing
                    time.sleep(0.2)  # Give pygame more time to start
                    if self.music.get_busy():
                        logger.info(f"Pygame mixer is playing successfully")
                        logger.info(f"Pygame mixer status: busy={self.music.get_busy()}")
                    else:
                        logger.warning(f"Pygame mixer is not playing - this indicates a problem")
                        logger.warning(f"Pygame mixer status: busy={self.music.get_busy()}")
                    
                    self.current_song = song_data
                    self.is_playing = True
                    self.start_time = time.time()
                    
                    # Get duration from actual audio data, not database
                    estimated_duration = self.estimate_duration_from_stream(audio_data)
                    if estimated_duration > 0:
                        self.duration = estimated_duration
                        logger.info(f"Using estimated duration from transcoded audio: {self.duration:.1f}s")
                    else:
                        # Fallback to database duration, but log warning
                        self.duration = song_data.get('duration', 0) or 0
                        logger.warning(f"Using database duration (may be unreliable): {self.duration}s")
                        
                    if self.duration <= 0:
                        logger.warning(f"Invalid song duration: {self.duration}s - this may cause crossfade issues")
                    self.next_song = None
                    self.next_song_data = None
                    self.next_song_preloaded = False
                    self.crossfade_start = 0
                    logger.info(f"Playing {song_data.get('title', 'Unknown')} - duration: {self.duration}s")
                    
                else:
                    # Only preload if we're very close to the end (crossfade timing)
                    remaining = self.get_remaining()
                    if remaining <= (self.crossfade_duration + self.prequeue_margin):
                        logger.info(f"Preloading audio data for crossfade (remaining: {remaining:.1f}s)")
                        self.next_song = pygame.mixer.Sound(audio_data)
                        self.next_song_data = song_data  # Store the song metadata
                        self.next_song_preloaded = True
                        logger.info(f"Preloaded {song_data.get('title', 'Unknown')} for crossfade")
                    else:
                        logger.info(f"Skipping preload - too early (remaining: {remaining:.1f}s)")
                        return True
                
                try:
                    self.redis_client.set('jukebox:current_song', json.dumps(song_data))
                except Exception as e:
                    logger.error(f"Error saving current song to Redis: {e}")
                return True
                
            except pygame.error as e:
                logger.warning(f"Pygame failed to load {stream_url}: {e}")
                logger.info("Trying ffmpeg transcoding as fallback")
                try:
                    audio_data = self._transcode_to_wav(stream_url)
                    if force_play or not self.is_playing:
                        logger.info(f"Loading transcoded audio data into pygame mixer")
                        self.music.load(audio_data)
                        logger.info(f"Starting pygame playback with transcoded audio")
                        self.music.play()
                        self.current_song = song_data
                        self.is_playing = True
                        self.start_time = time.time()
                        self.duration = song_data.get('duration', 0) or 0
                        logger.info(f"Song duration from database: {self.duration}s")
                        if self.duration <= 0:
                            logger.warning(f"Invalid song duration: {self.duration}s - this may cause crossfade issues")
                        self.next_song = None
                        self.next_song_data = None
                        self.next_song_preloaded = False
                        self.crossfade_start = 0
                        logger.info(f"Playing {song_data.get('title', 'Unknown')} via ffmpeg - duration: {self.duration}s")
                    else:
                        # Only preload if we're very close to the end
                        remaining = self.get_remaining()
                        if remaining <= (self.crossfade_duration + self.prequeue_margin):
                            logger.info(f"Preloading transcoded audio data for crossfade (remaining: {remaining:.1f}s)")
                            self.next_song = pygame.mixer.Sound(audio_data)
                            self.next_song_data = song_data  # Store the song metadata
                            self.next_song_preloaded = True
                            logger.info(f"Preloaded {song_data.get('title', 'Unknown')} for crossfade via ffmpeg")
                        else:
                            logger.info(f"Skipping preload - too early (remaining: {remaining:.1f}s)")
                            return True
                            
                    try:
                        self.redis_client.set('jukebox:current_song', json.dumps(song_data))
                    except Exception as e:
                        logger.error(f"Error saving current song to Redis: {e}")
                    return True
                    
                except Exception as ffmpeg_error:
                    logger.error(f"FFmpeg transcoding also failed: {ffmpeg_error}")
                    return False
                    
        except Exception as e:
            logger.error(f"Error playing song: {e}")
            return False

    def stop_playback(self):
        """Stop playback"""
        self.music.stop()
        self.next_channel.stop()
        self.is_playing = False
        self.current_song = None
        self.next_song = None
        self.next_song_data = None  # Clear the song metadata
        self.next_song_preloaded = False
        self.duration = 0
        self.start_time = 0
        self.paused_time = 0
        self.crossfade_start = 0

    def pause_playback(self):
        """Pause playback"""
        if self.is_playing:
            self.music.pause()
            self.next_channel.stop()
            self.is_playing = False
            self.paused_time = time.time() - self.start_time
            self.next_song = None
            self.next_song_data = None  # Clear the song metadata
            self.next_song_preloaded = False
            self.crossfade_start = 0

    def resume_playback(self):
        """Resume playback"""
        if not self.is_playing and self.paused_time > 0:
            self.music.unpause()
            self.is_playing = True
            self.start_time = time.time() - self.paused_time
            self.paused_time = 0

    def set_volume(self, volume: int):
        """Set volume"""
        self.volume = max(0, min(100, volume))
        self.music.set_volume(self.volume / 100.0)
        if self.next_song_preloaded:
            self.next_channel.set_volume(0.0)
        try:
            self.redis_client.set('jukebox:current_volume', self.volume)
        except Exception as e:
            logger.error(f"Error saving volume to Redis: {e}")

    def get_elapsed(self) -> float:
        """Get elapsed time"""
        if self.is_playing:
            return time.time() - self.start_time
        return self.paused_time

    def get_remaining(self) -> float:
        """Get remaining time"""
        return max(0.0, self.duration - self.get_elapsed())

    def is_audio_playing(self) -> bool:
        """Check if pygame mixer is actually playing audio"""
        try:
            return self.music.get_busy()
        except Exception as e:
            logger.error(f"Error checking pygame mixer status: {e}")
            return False

    def get_audio_status(self) -> Dict:
        """Get detailed audio playback status"""
        try:
            return {
                'pygame_busy': self.music.get_busy(),
                'is_playing': self.is_playing,
                'elapsed': self.get_elapsed(),
                'duration': self.duration,
                'remaining': self.get_remaining(),
                'volume': self.volume,
                'crossfade_active': self.crossfade_start > 0,
                'next_song_preloaded': self.next_song_preloaded
            }
        except Exception as e:
            logger.error(f"Error getting audio status: {e}")
            return {}

    def get_actual_audio_duration(self) -> float:
        """Get actual audio duration from pygame mixer - more reliable than database"""
        try:
            # Try to get duration from pygame mixer if available
            if hasattr(self.music, 'get_length'):
                # Some pygame versions support this
                return self.music.get_length()
            elif hasattr(self.music, 'get_pos'):
                # Alternative method - get current position
                pos = self.music.get_pos()
                if pos > 0:
                    # Estimate duration based on position and elapsed time
                    elapsed = self.get_elapsed()
                    if elapsed > 0:
                        # Rough estimate: if we're 10% through, duration = elapsed * 10
                        # This is approximate but better than trusting database
                        return elapsed * 10
            return 0.0
        except Exception as e:
            logger.debug(f"Could not get actual audio duration: {e}")
            return 0.0

    def estimate_duration_from_stream(self, audio_data: BytesIO) -> float:
        """Estimate duration from audio data size and format"""
        try:
            # For WAV files, we can calculate duration from file size
            # WAV header is 44 bytes, then 2 channels * 2 bytes per sample * 44100 samples per second
            if len(audio_data.getvalue()) > 44:
                # Skip header, calculate from PCM data
                pcm_size = len(audio_data.getvalue()) - 44
                # 2 channels * 2 bytes per sample * 44100 samples per second = 176400 bytes per second
                duration = pcm_size / 176400.0
                logger.info(f"Estimated duration from WAV data: {duration:.1f}s")
                return duration
            return 0.0
        except Exception as e:
            logger.debug(f"Could not estimate duration from stream: {e}")
            return 0.0

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
                    action_plan['volume_action'] = cmd_data
                elif action == 'set_crossfade':
                    action_plan['crossfade_action'] = cmd_data
            except Exception as e:
                logger.error(f"Invalid command: {cmd}, error: {e}")
        return action_plan

    def execute_action_plan(self, action_plan: Dict):
        """Execute collapsed commands"""
        if 'state_action' in action_plan:
            action = action_plan['state_action']
            if action == 'stop':
                self.desired_state = 'stopped'
                self.stop_playback()
            elif action == 'pause':
                if self.desired_state != 'paused':
                    self.desired_state = 'paused'
                    self.pause_playback()
            elif action == 'play':
                self.desired_state = 'playing'
                if self.current_song:
                    self.resume_playback()
                else:
                    if not self.play_song(self.get_next_song(), force_play=True):
                        self.desired_state = 'stopped'
                        self.stop_playback()
            self._save_desired_state()

        if 'volume_action' in action_plan:
            cmd = action_plan['volume_action']
            action = cmd.get('action')
            current_volume = self.volume
            if action == 'set_volume':
                volume = max(0, min(100, int(cmd.get('value', current_volume))))
            elif action == 'volume_up':
                volume = min(100, current_volume + 10)
            elif action == 'volume_down':
                volume = max(0, current_volume - 10)
            self.set_volume(volume)

        if 'crossfade_action' in action_plan:
            duration = int(max(0, min(100, action_plan['crossfade_action'].get('value', 0))))
            self.crossfade_duration = duration * 1000

    def update_status(self):
        """Poll playback and write status to Redis"""
        try:
            actual_state = 'playing' if self.is_playing else 'paused' if self.paused_time > 0 else 'stopped'
            elapsed = self.get_elapsed()
            remaining = max(0.0, self.duration - elapsed) if self.duration else 0.0
            progress = round((elapsed / self.duration * 100) if self.duration > 0 else 0, 1)
            volume = self.volume
            crossfade = self.crossfade_duration // 1000
            error_message = ''
            health = 'healthy'
            
            # Debug timing information
            if self.is_playing and self.duration > 0:
                logger.debug(f"Timing: elapsed={elapsed:.1f}s, duration={self.duration}s, remaining={remaining:.1f}s, progress={progress}%")
                
                # Get real-time metrics from pygame
                real_metrics = self.get_real_time_metrics()
                if real_metrics.get('position_seconds'):
                    logger.debug(f"Real-time: pygame_pos={real_metrics['position_seconds']:.1f}s, actual_elapsed={real_metrics.get('actual_elapsed', 0):.1f}s")

            # Reconcile desired vs actual state
            if actual_state != self.desired_state:
                if self.desired_state == 'playing' and actual_state != 'playing':
                    if not self.play_song(self.get_next_song(), force_play=True):
                        self.desired_state = 'stopped'
                        self.stop_playback()
                        error_message = 'No next song available'
                elif self.desired_state == 'paused' and actual_state == 'playing':
                    self.pause_playback()
                elif self.desired_state == 'stopped':
                    self.stop_playback()
                self._save_desired_state()

            # Handle crossfade - only preload when song is actually near the end
            threshold = self.crossfade_duration / 1000 + self.prequeue_margin
            if (self.desired_state == 'playing' and 
                self.is_playing and 
                not self.next_song_preloaded and 
                remaining > 0 and  # Make sure song is actually playing
                elapsed > 5 and  # Make sure song has been playing for at least 5 seconds
                remaining <= threshold):
                logger.info(f"Song near end - preloading next song (remaining: {remaining:.1f}s, elapsed: {elapsed:.1f}s)")
                next_song_data = self.get_next_song()
                if next_song_data:
                    self.play_song(next_song_data, force_play=False)
                else:
                    self.desired_state = 'stopped'
                    self.stop_playback()
                    error_message = 'No next song available'
            elif self.desired_state == 'playing' and self.is_playing and not self.next_song_preloaded:
                # Debug why crossfade isn't happening
                logger.debug(f"Crossfade conditions not met: remaining={remaining:.1f}s, elapsed={elapsed:.1f}s, threshold={threshold:.1f}s")

            # Perform crossfade - only when song is actually ending
            if (self.is_playing and 
                self.next_song_preloaded and 
                remaining > 0 and  # Make sure song is actually playing
                elapsed > 5 and  # Make sure song has been playing for at least 5 seconds
                remaining <= (self.crossfade_duration / 1000)):
                if not self.crossfade_start:
                    logger.info(f"Starting crossfade (remaining: {remaining:.1f}s, elapsed: {elapsed:.1f}s)")
                    self.next_channel.play(self.next_song)
                    self.next_channel.set_volume(0.0)
                    self.crossfade_start = time.time()
                    logger.info("Starting crossfade")
                elapsed_crossfade = (time.time() - self.crossfade_start) * 1000
                if elapsed_crossfade < self.crossfade_duration:
                    current_vol = max(0, self.volume * (1 - elapsed_crossfade / self.crossfade_duration))
                    next_vol = self.volume * (elapsed_crossfade / self.crossfade_duration)
                    self.music.set_volume(current_vol / 100.0)
                    self.next_channel.set_volume(next_vol / 100.0)
                else:
                    self.music.stop()
                    # Store the next song data before clearing it
                    next_song_data = self.next_song_data
                    self.current_song = next_song_data
                    self.next_song = None
                    self.next_song_preloaded = False
                    self.crossfade_start = 0
                    # Load and play the next song
                    try:
                        response = requests.get(next_song_data.get('stream_url'))
                        if response.status_code == 200:
                            audio_data = BytesIO(response.content)
                            self.music.load(audio_data)
                            self.music.play()
                            self.start_time = time.time() - (self.duration - remaining)
                            
                            # Get duration from actual audio data for the next song
                            estimated_duration = self.estimate_duration_from_stream(audio_data)
                            if estimated_duration > 0:
                                self.duration = estimated_duration
                                logger.info(f"Crossfade complete - next song duration from stream: {self.duration:.1f}s")
                            else:
                                # Fallback to database duration
                                self.duration = next_song_data.get('duration', 0) or 0
                                logger.warning(f"Crossfade complete - using database duration: {self.duration}s")
                            
                            self.music.set_volume(self.volume / 100.0)
                            logger.info(f"Crossfade complete, playing {next_song_data.get('title', 'Unknown')}")
                        else:
                            logger.error(f"Failed to load next song for crossfade: {response.status_code}")
                    except Exception as e:
                        logger.error(f"Error loading next song for crossfade: {e}")
            elif self.is_playing and self.next_song_preloaded:
                # Debug why crossfade execution isn't happening
                logger.debug(f"Crossfade execution conditions not met: remaining={remaining:.1f}s, elapsed={elapsed:.1f}s, crossfade_threshold={(self.crossfade_duration / 1000):.1f}s")

            # Write status
            status_data = {
                'timestamp': str(time.time()),
                'desired_state': self.desired_state,
                'actual_state': actual_state,
                'elapsed_seconds': str(elapsed),
                'duration_seconds': str(self.duration),
                'volume': str(volume),
                'crossfade_seconds': str(crossfade),
                'time_until_next_request': str(max(0, remaining - threshold) if self.is_playing else 0),
                'current_song_metadata': json.dumps(self.current_song or {}),
                'error_message': error_message,
                'health': health,
                'remaining_seconds': str(remaining),
                'progress_percent': str(progress)
            }
            
            # Add audio debugging info
            if self.is_playing:
                audio_status = self.get_audio_status()
                logger.debug(f"Audio status: pygame_busy={audio_status.get('pygame_busy')}, "
                           f"elapsed={audio_status.get('elapsed'):.1f}s, "
                           f"remaining={audio_status.get('remaining'):.1f}s")
                
                # Check if pygame thinks it's playing but we're not getting audio
                if audio_status.get('pygame_busy') and elapsed > 10 and remaining > 0:
                    logger.warning(f"Pygame thinks it's playing but elapsed time is {elapsed:.1f}s - possible audio issue")
                
                # Check if the audio is actually progressing
                if hasattr(self, '_last_elapsed'):
                    time_diff = elapsed - self._last_elapsed
                    if time_diff < 0.5:  # If time isn't progressing much
                        logger.warning(f"Audio time not progressing normally: {time_diff:.2f}s elapsed in 1s loop")
                self._last_elapsed = elapsed
            
            try:
                self.redis_client.hset('jukebox:player_status', mapping=status_data)
            except Exception as e:
                logger.error(f"Error writing status to Redis: {e}")

        except Exception as e:
            logger.error(f"Error polling playback: {e}")
            self.desired_state = 'stopped'
            self.stop_playback()
            error_message = str(e)
            health = 'unhealthy'
            status_data = {
                'timestamp': str(time.time()),
                'desired_state': self.desired_state,
                'actual_state': 'stop',
                'elapsed_seconds': '0',
                'duration_seconds': '0',
                'volume': str(self.volume),
                'crossfade_seconds': str(self.crossfade_duration // 1000),
                'time_until_next_request': '0',
                'current_song_metadata': '{}',
                'error_message': error_message,
                'health': health,
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
                try:
                    commands = self.redis_client.lrange('jukebox:commands', 0, -1)
                    if commands:
                        self.redis_client.delete('jukebox:commands')
                        action_plan = self.collapse_commands(commands)
                        self.execute_action_plan(action_plan)
                except Exception as e:
                    logger.error(f"Error processing commands: {e}")
                self.update_status()
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
        self.stop_playback()
        try:
            self.redis_client.set('jukebox:status', json.dumps({
                'state': 'stopped',
                'timestamp': time.time()
            }))
        except Exception:
            pass
        pygame.mixer.quit()
        logger.info("Shutdown complete")

    def get_real_time_metrics(self) -> Dict:
        """Get real-time audio metrics from pygame mixer"""
        try:
            metrics = {
                'pygame_busy': self.music.get_busy(),
                'volume': self.volume,
                'crossfade_active': self.crossfade_start > 0
            }
            
            # Try to get position from pygame if available
            if hasattr(self.music, 'get_pos'):
                try:
                    pos_ms = self.music.get_pos()
                    if pos_ms > 0:
                        metrics['position_ms'] = pos_ms
                        metrics['position_seconds'] = pos_ms / 1000.0
                except Exception as e:
                    logger.debug(f"Could not get pygame position: {e}")
            
            # Calculate actual elapsed time
            if self.start_time > 0:
                metrics['actual_elapsed'] = time.time() - self.start_time
                metrics['actual_remaining'] = max(0, self.duration - metrics['actual_elapsed'])
            
            return metrics
        except Exception as e:
            logger.error(f"Error getting real-time metrics: {e}")
            return {}

if __name__ == "__main__":
    player = JukeboxPlayer()
    player.run()