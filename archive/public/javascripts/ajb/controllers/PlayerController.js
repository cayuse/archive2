// AJB PlayerController - Business logic for the player
class PlayerController {
  constructor(jukeboxId, apiToken) {
    console.log('🔍 PlayerController constructor called with:', { jukeboxId, apiTokenLength: apiToken?.length });
    this.jukeboxId = jukeboxId;
    this.apiToken = apiToken;
    
    console.log('🔍 Creating AudioEngine...');
    this.audioEngine = new AudioEngine();
    
    console.log('🔍 Creating PlaybackState...');
    this.playbackState = new PlaybackState();
    
    console.log('🔍 Creating ApiService...');
    this.apiService = new ApiService(jukeboxId, apiToken);
    
    this.isLoading = false;
    
    this.setupEventHandlers();
    this.startTimeUpdateLoop();
  }

  setupEventHandlers() {
    // Audio engine events
    this.audioEngine.onPlay = () => {
      this.playbackState.setPlaybackStatus(true, false, false);
    };

    this.audioEngine.onPause = () => {
      this.playbackState.setPlaybackStatus(false, true, false);
    };

    this.audioEngine.onStop = () => {
      this.playbackState.setPlaybackStatus(false, false, true);
    };

    this.audioEngine.onEnd = () => {
      this.playbackState.setPlaybackStatus(false, false, true);
      this.playNextSong();
    };

    this.audioEngine.onError = (error) => {
      console.error('Audio error:', error);
      this.playbackState.setPlaybackStatus(false, false, true);
      this.notifyError('Audio playback error');
    };

    this.audioEngine.onSkip = () => {
      this.playNextSong();
    };

    // Playback state events
    this.playbackState.onStateChange = (state) => {
      this.updatePlaybackStatus();
    };

    this.playbackState.onSongChange = (song) => {
      this.notifySongChange(song);
    };

    this.playbackState.onTimeUpdate = (currentTime, duration) => {
      this.notifyTimeUpdate(currentTime, duration);
    };
  }

  // Start time update loop
  startTimeUpdateLoop() {
    setInterval(() => {
      if (this.audioEngine.isPlaying) {
        const currentTime = this.audioEngine.getCurrentTime();
        const duration = this.audioEngine.getDuration();
        this.playbackState.updateTime(currentTime, duration);
      }
    }, 1000); // Update every second
  }

  // Play the next song
  async playNextSong() {
    if (this.isLoading) return;
    
    this.isLoading = true;
    this.notifyLoading(true);

    try {
      const result = await this.apiService.getNextSong();
      
      if (result.success && result.song) {
        const song = result.song;
        this.playbackState.setCurrentSong(song);
        
        const loaded = await this.audioEngine.loadAndPlay(song);
        if (loaded) {
          console.log(`Playing: ${song.title} by ${song.artist}`);
        } else {
          this.notifyError('Failed to load song');
        }
      } else {
        this.notifyError(result.message || 'No songs available');
      }
    } catch (error) {
      console.error('Error getting next song:', error);
      this.notifyError('Error getting next song');
    } finally {
      this.isLoading = false;
      this.notifyLoading(false);
    }
  }

  // Play button
  async play() {
    if (!this.playbackState.currentSong) {
      await this.playNextSong();
    } else {
      this.audioEngine.play();
    }
  }

  // Pause button
  pause() {
    this.audioEngine.pause();
  }

  // Stop button
  stop() {
    this.audioEngine.stop();
  }

  // Skip button (>>|)
  skip() {
    this.audioEngine.skip();
  }

  // Restart button (|<<)
  restart() {
    this.audioEngine.restart();
  }

  // Update playback status on server
  async updatePlaybackStatus() {
    try {
      const state = this.playbackState.getState();
      await this.apiService.updatePlaybackStatus({
        current_song_id: state.currentSong ? state.currentSong.id : null,
        position: state.currentTime,
        is_playing: state.isPlaying,
        volume: state.volume
      });
    } catch (error) {
      console.warn('Playback status update failed (this is non-critical):', error.message);
      // Don't throw the error - this is just for real-time sync, not core functionality
    }
  }

  // Get current state
  getState() {
    return this.playbackState.getState();
  }

  // Set volume
  setVolume(volume) {
    this.audioEngine.setVolume(volume);
    this.playbackState.setVolume(volume);
  }

  // Event callbacks (to be set by view)
  notifyLoading(isLoading) {
    if (this.onLoading) {
      this.onLoading(isLoading);
    }
  }

  notifyError(message) {
    if (this.onError) {
      this.onError(message);
    }
  }

  notifySongChange(song) {
    if (this.onSongChange) {
      this.onSongChange(song);
    }
  }

  notifyTimeUpdate(currentTime, duration) {
    if (this.onTimeUpdate) {
      this.onTimeUpdate(currentTime, duration);
    }
  }

  // Clean up
  destroy() {
    this.audioEngine.destroy();
  }
}