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
  }

  // Load and play a song
  async loadAndPlay(song) {
    try {
      this.currentSong = song;
      
      // Clean up previous sound
      if (this.sound) {
        this.sound.unload();
      }

      // Create new Howl instance
      this.sound = new Howl({
        src: [song.download_url],
        format: ['mp3', 'm4a', 'ogg'],
        volume: this.currentVolume, // Apply persistent volume setting
        onload: () => {
          console.log('Audio: Loaded successfully');
        },
        onplay: () => {
          this.isPlaying = true;
          this.isPaused = false;
          this.isStopped = false;
          console.log('Audio: Started playing');
          if (this.onPlay) this.onPlay();
        },
        onpause: () => {
          this.isPlaying = false;
          this.isPaused = true;
          console.log('Audio: Paused');
          if (this.onPause) this.onPause();
        },
        onstop: () => {
          this.isPlaying = false;
          this.isPaused = false;
          this.isStopped = true;
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
          if (this.onError) this.onError(error);
        }
      });

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

  // Clean up
  destroy() {
    if (this.sound) {
      this.sound.unload();
      this.sound = null;
    }
  }
}