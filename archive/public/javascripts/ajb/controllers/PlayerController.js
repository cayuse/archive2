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
    this.pauseAfterSong = false;   // armed: hold when the current track ends
    this.awaitingResume = false;   // held between songs, waiting for the host
    this.queue = [];
    this.history = [];
    this.historyPage = 0;
    this.historyHasMore = true;
    this.historyLoading = false;
    this.historyPerPage = 25;
    this.cableSubscription = null;

    this.setupEventHandlers();
    this.startTimeUpdateLoop();

    // Show the host the live queue (incl. guest requests) + recent history.
    this.loadQueue();
    this.loadHistory();
    this.subscribeRealtime();
    this.startHeartbeat();
  }

  // Heartbeat: while this player is open it reports status periodically (even
  // when paused/idle), which keeps the jukebox "live". When the page closes the
  // heartbeat stops and the jukebox goes offline on the server side.
  startHeartbeat() {
    this.updatePlaybackStatus();
    this.heartbeatInterval = setInterval(() => this.updatePlaybackStatus(), 10000);
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
      if (this.pauseAfterSong) {
        // Hold between songs (e.g. for an announcement) instead of advancing.
        this.pauseAfterSong = false;
        this.awaitingResume = true;
        this.notifyPauseMode();
      } else {
        this.playNextSong();
      }
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

    // Advancing clears any pending "pause after song" hold.
    if (this.awaitingResume) {
      this.awaitingResume = false;
      this.notifyPauseMode();
    }

    this.isLoading = true;
    this.notifyLoading(true);

    try {
      const result = await this.apiService.getNextSong();
      
      if (result.success && result.song) {
        const song = result.song;
        this.playbackState.setCurrentSong(song);
        this.loadQueue();          // the consumed track left the queue
        this.refreshNewestHistory(); // ...and became a history entry

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
    if (this.awaitingResume) {
      // Resume after a "pause after song" hold → continue to the next track.
      await this.playNextSong();
      return;
    }
    if (!this.playbackState.currentSong) {
      await this.playNextSong();
    } else {
      this.audioEngine.play();
    }
  }

  // Arm/disarm "pause after current song".
  togglePauseAfterSong() {
    this.pauseAfterSong = !this.pauseAfterSong;
    this.notifyPauseMode();
  }

  notifyPauseMode() {
    if (this.onPauseModeChange) this.onPauseModeChange(this.pauseAfterSong, this.awaitingResume);
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

  // Load a page of history. reset=true starts over at page 1 (replace);
  // reset=false appends the next page (infinite scroll).
  async loadHistory(reset = true) {
    if (this.historyLoading) return;
    if (!reset && !this.historyHasMore) return;
    this.historyLoading = true;
    const page = reset ? 1 : this.historyPage + 1;
    try {
      const result = await this.apiService.getHistory(page, this.historyPerPage);
      if (result.success) {
        const items = result.history || [];
        if (reset) {
          this.history = items;
        } else {
          const known = new Set(this.history.map(h => h.id));
          this.history = this.history.concat(items.filter(h => !known.has(h.id)));
        }
        this.historyPage = page;
        this.historyHasMore = result.pagination ? !!result.pagination.has_more : false;
        this.notifyHistoryChange();
      }
    } catch (error) {
      console.warn('Failed to load history:', error.message);
    } finally {
      this.historyLoading = false;
    }
  }

  loadMoreHistory() {
    return this.loadHistory(false);
  }

  // Prepend any newly-played songs to the top without disturbing the scroll
  // position / already-loaded pages.
  async refreshNewestHistory() {
    const result = await this.apiService.getHistory(1, this.historyPerPage);
    if (result.success) {
      const known = new Set(this.history.map(h => h.id));
      const fresh = (result.history || []).filter(h => !known.has(h.id));
      if (fresh.length) {
        this.history = fresh.concat(this.history);
        this.notifyHistoryChange();
      }
    }
  }

  // Re-request a song from history (host "play it again"); adds it to the queue.
  async requestFromHistory(songId) {
    const result = await this.apiService.addToQueue(songId, 'requested');
    if (result.success) {
      await this.loadQueue();
    } else {
      this.notifyError(result.message || 'Could not re-request song');
    }
    return result;
  }

  notifyHistoryChange() {
    if (this.onHistoryChange) this.onHistoryChange(this.history, this.historyHasMore);
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
            this.refreshNewestHistory(); // a consumed track became a history entry
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
    if (this.heartbeatInterval) {
      clearInterval(this.heartbeatInterval);
      this.heartbeatInterval = null;
    }
    if (this.cableSubscription) {
      this.cableSubscription.unsubscribe();
      this.cableSubscription = null;
    }
  }
}