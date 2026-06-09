// AJB AudioEngine - Howler.js based audio player
class AudioEngine {
  constructor() {
    this.sound = null;
    this.currentSong = null;
    this.isPlaying = false;
    this.isPaused = false;
    this.isStopped = true;
    this.currentVolume = 0.8; // Persistent volume setting (default 80%)
    
    // Initialize Howler
    if (typeof Howl === 'undefined') {
      throw new Error('Howler.js is required but not loaded');
    }

    // Wire up OS-level media controls (lock screen / control center) so playback
    // is treated as a background-audio session and keeps going when the screen
    // sleeps. Handlers are registered once and reused for every track.
    this.setupMediaSession();
  }

  // Load and play a song
  async loadAndPlay(song) {
    try {
      this.currentSong = song;
      
      // Clean up previous sound
      if (this.sound) {
        this.sound.unload();
      }

      // Create new Howl instance.
      // html5: true forces playback through an HTML5 <audio> element instead of
      // the Web Audio API. iOS/iPadOS suspends the Web Audio context when the
      // screen locks (killing playback), but allows an <audio> element to keep
      // playing in the background — so this is what lets the jukebox survive a
      // sleeping phone/tablet. Prefer the Range-capable stream endpoint.
      this.sound = new Howl({
        src: [song.stream_url || song.download_url],
        format: ['mp3', 'm4a', 'ogg'],
        html5: true,
        volume: this.currentVolume, // Apply persistent volume setting
        onload: () => {
          console.log('Audio: Loaded successfully');
        },
        onplay: () => {
          this.isPlaying = true;
          this.isPaused = false;
          this.isStopped = false;
          this.setMediaSessionPlaybackState('playing');
          console.log('Audio: Started playing');
          if (this.onPlay) this.onPlay();
        },
        onpause: () => {
          this.isPlaying = false;
          this.isPaused = true;
          this.setMediaSessionPlaybackState('paused');
          console.log('Audio: Paused');
          if (this.onPause) this.onPause();
        },
        onstop: () => {
          this.isPlaying = false;
          this.isPaused = false;
          this.isStopped = true;
          this.setMediaSessionPlaybackState('none');
          console.log('Audio: Stopped');
          if (this.onStop) this.onStop();
        },
        onend: () => {
          this.isPlaying = false;
          this.isPaused = false;
          this.isStopped = true;
          console.log('Audio: Ended');
          if (this.onEnd) this.onEnd();
        },
        onerror: (id, error) => {
          console.error('Audio error:', error);
          this.isPlaying = false;
          this.isPaused = false;
          this.isStopped = true;
          this.setMediaSessionPlaybackState('none');
          if (this.onError) this.onError(error);
        }
      });

      // Surface the track on the OS lock screen / control center.
      this.updateMediaSessionMetadata(song);

      // Play the sound
      this.sound.play();
      return true;
    } catch (error) {
      console.error('Failed to load and play song:', error);
      return false;
    }
  }

  // Play current song
  play() {
    if (this.sound && (this.isPaused || this.isStopped)) {
      this.sound.play();
    }
  }

  // Pause current song
  pause() {
    if (this.sound && this.isPlaying) {
      this.sound.pause();
    }
  }

  // Stop current song
  stop() {
    if (this.sound) {
      this.sound.stop();
    }
  }

  // Skip to beginning of current song
  restart() {
    if (this.sound) {
      this.sound.seek(0);
      if (this.isStopped) {
        this.play();
      }
    }
  }

  // Skip to next song
  skip() {
    this.stop();
    if (this.onSkip) {
      this.onSkip();
    }
  }

  // Get current playback info
  getPlaybackInfo() {
    return {
      currentSong: this.currentSong,
      currentTime: this.sound ? this.sound.seek() : 0,
      duration: this.sound ? this.sound.duration() : 0,
      isPlaying: this.isPlaying,
      isPaused: this.isPaused,
      isStopped: this.isStopped
    };
  }

  // Set volume (0.0 to 1.0)
  setVolume(volume) {
    // Clamp volume to valid range
    this.currentVolume = Math.max(0, Math.min(1, volume));
    
    // Apply to current sound if it exists
    if (this.sound) {
      this.sound.volume(this.currentVolume);
    }
  }

  // Get current volume
  getVolume() {
    return this.currentVolume;
  }

  // Get current time
  getCurrentTime() {
    return this.sound ? this.sound.seek() : 0;
  }

  // Get duration
  getDuration() {
    return this.sound ? this.sound.duration() : 0;
  }

  // --- MediaSession (OS lock-screen / background-audio integration) ---

  // Register the OS media-key / lock-screen action handlers once. These let the
  // user control playback from the lock screen or control center, and signal to
  // iOS/Android that this is an audio app that should keep running in the
  // background.
  setupMediaSession() {
    if (!('mediaSession' in navigator)) return;

    const set = (action, handler) => {
      try {
        navigator.mediaSession.setActionHandler(action, handler);
      } catch (e) {
        // Some browsers don't support every action; ignore the unsupported ones.
      }
    };

    set('play', () => this.play());
    set('pause', () => this.pause());
    set('stop', () => this.stop());
    set('nexttrack', () => this.skip());
    set('previoustrack', () => this.restart());
  }

  // Push the current track's info to the lock screen.
  updateMediaSessionMetadata(song) {
    if (!('mediaSession' in navigator) || !song) return;
    try {
      navigator.mediaSession.metadata = new MediaMetadata({
        title: song.title || 'Unknown Title',
        artist: song.artist || 'Unknown Artist',
        album: song.album || ''
      });
    } catch (e) {
      console.warn('MediaSession metadata update failed:', e);
    }
  }

  setMediaSessionPlaybackState(state) {
    if (!('mediaSession' in navigator)) return;
    try {
      navigator.mediaSession.playbackState = state; // 'playing' | 'paused' | 'none'
    } catch (e) {
      // Non-critical.
    }
  }

  // Feed the lock-screen scrubber the current position. Called from the time loop.
  updateMediaSessionPosition() {
    if (!('mediaSession' in navigator) || typeof navigator.mediaSession.setPositionState !== 'function') return;
    const duration = this.getDuration();
    if (!duration || !isFinite(duration)) return;
    try {
      navigator.mediaSession.setPositionState({
        duration: duration,
        position: Math.min(this.getCurrentTime(), duration),
        playbackRate: 1
      });
    } catch (e) {
      // Non-critical.
    }
  }

  // Clean up
  destroy() {
    if (this.sound) {
      this.sound.unload();
      this.sound = null;
    }
  }
}