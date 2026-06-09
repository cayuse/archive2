// AJB PlayerController - Business logic for the player
class PlayerController {
  constructor(jukeboxId, apiToken, sessionId = null) {
    this.jukeboxId = jukeboxId;
    this.apiToken = apiToken;
    this.sessionId = sessionId;

    this.audioEngine = new AudioEngine();
    this.playbackState = new PlaybackState();
    this.apiService = new ApiService(jukeboxId, apiToken);

    this.isLoading = false;
    this.queue = [];
    this.history = [];
    this.cableSubscription = null;

    this.setupEventHandlers();
    this.startTimeUpdateLoop();

    // Show the host the live queue (incl. guest requests) + recent history.
    this.loadQueue();
    this.loadHistory();
    this.subscribeRealtime();
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
        // Keep the lock-screen scrubber in sync.
        this.audioEngine.updateMediaSessionPosition();
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
        this.loadQueue();   // the consumed track left the queue
        this.loadHistory(); // ...and became a history entry

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

  // --- Queue management: the host's view of upcoming songs + guest requests ---

  async loadQueue() {
    try {
      const result = await this.apiService.getQueue();
      if (result.success) {
        this.queue = result.queue || [];
        this.notifyQueueChange();
      }
    } catch (error) {
      console.warn('Failed to load queue:', error.message);
    }
  }

  async removeFromQueue(songId) {
    const result = await this.apiService.removeFromQueue(songId);
    if (result.success) {
      await this.loadQueue();
    } else {
      this.notifyError(result.message || 'Could not remove song from queue');
    }
    return result;
  }

  async promoteInQueue(songId) {
    const result = await this.apiService.promoteInQueue(songId);
    if (result.success) await this.loadQueue();
    else this.notifyError(result.message || 'Could not promote song');
    return result;
  }

  async playNextInQueue(songId) {
    const result = await this.apiService.playNextInQueue(songId);
    if (result.success) await this.loadQueue();
    else this.notifyError(result.message || 'Could not move song');
    return result;
  }

  async loadHistory() {
    try {
      const result = await this.apiService.getHistory();
      if (result.success) {
        this.history = result.history || [];
        this.notifyHistoryChange();
      }
    } catch (error) {
      console.warn('Failed to load history:', error.message);
    }
  }

  notifyHistoryChange() {
    if (this.onHistoryChange) this.onHistoryChange(this.history);
  }

  // Live queue updates (a guest request / consumed track repaints the list).
  subscribeRealtime() {
    if (!this.sessionId || !(window.App && window.App.cable)) return;
    this.cableSubscription = window.App.cable.subscriptions.create(
      { channel: 'JukeboxChannel', session_id: this.sessionId },
      {
        received: (message) => {
          if (message && message.type === 'queue_update') {
            this.loadQueue();
            this.loadHistory(); // a consumed track became a history entry
          }
        }
      }
    );
  }

  notifyQueueChange() {
    if (this.onQueueChange) this.onQueueChange(this.queue);
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
    if (this.cableSubscription) {
      this.cableSubscription.unsubscribe();
      this.cableSubscription = null;
    }
  }
}