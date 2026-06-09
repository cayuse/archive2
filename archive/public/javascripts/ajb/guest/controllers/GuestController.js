// Guest Controller - Business logic for the guest interface
class GuestController {
  constructor(jukeboxId, password = null, sessionId = null) {
    this.jukeboxId = jukeboxId;
    this.password = password;
    this.sessionId = sessionId;
    this.apiService = new GuestApiService(jukeboxId, password);
    this.state = new GuestState();
    this.updateInterval = null;
    this.cableSubscription = null;

    // Play-history pagination (infinite scroll)
    this.historyItems = [];
    this.historyPage = 0;
    this.historyHasMore = true;
    this.historyLoading = false;
    this.historyPerPage = 25;

    this.setupEventHandlers();
  }

  setupEventHandlers() {
    // Set up state change listeners
    this.state.subscribe((state) => {
      this.handleStateChange(state);
    });
  }

  handleStateChange(state) {
    // Handle any global state changes
    console.log('Guest state changed:', state);
  }

  // Authentication. The password typed into the AuthView is passed in here and
  // applied to the controller + api service before the first request, otherwise
  // getStatus() would go out with the (null) password the controller was built
  // with and the server would 401.
  async authenticate(password = null) {
    try {
      if (password !== null) {
        this.password = password;
        this.apiService.password = password;
      }

      this.state.setLoading(true);
      this.state.clearError();

      const result = await this.apiService.getStatus();
      if (result.success) {
        this.state.setAuthentication(this.jukeboxId, this.password);
        this.state.setState({
          jukeboxName: result.jukebox.name,
          jukeboxStatus: result.jukebox.status,
          currentSong: result.jukebox.current_song_id ? {
            id: result.jukebox.current_song_id,
            position: result.jukebox.current_position,
            is_playing: result.jukebox.is_playing
          } : null,
          currentPosition: result.jukebox.current_position || 0,
          isPlaying: result.jukebox.is_playing || false,
          volume: result.jukebox.volume || 0.8
        });
        
        // Live updates over ActionCable, with a slow poll as a safety net.
        this.subscribeRealtime();
        this.refreshNow();
        this.startPeriodicUpdates();

        return { success: true };
      }
    } catch (error) {
      this.state.setError(error.message);
      return { success: false, error: error.message };
    } finally {
      this.state.setLoading(false);
    }
  }

  // Subscribe to live jukebox updates over ActionCable. Now-playing changes and
  // queue changes are pushed instantly; the periodic poll below is only a
  // fallback for when the socket is unavailable or a message is missed.
  subscribeRealtime() {
    if (!this.sessionId || !(window.App && window.App.cable)) {
      console.warn('Live updates unavailable; relying on periodic polling.');
      return;
    }
    this.cableSubscription = window.App.cable.subscriptions.create(
      { channel: 'JukeboxChannel', session_id: this.sessionId },
      {
        received: (message) => this.handleRealtimeMessage(message),
        connected: () => console.log('Jukebox live updates connected'),
        disconnected: () => console.log('Jukebox live updates disconnected')
      }
    );
  }

  handleRealtimeMessage(message) {
    if (!message || !message.type) return;
    switch (message.type) {
      case 'playback_status_update': {
        const d = message.data || {};
        this.state.setCurrentSong(d.current_song || null, d.position || 0, d.is_playing || false);
        break;
      }
      case 'queue_update':
        this.updateQueue();
        this.refreshNewestHistory(); // a consumed track became a history entry
        break;
    }
  }

  // One-shot refresh used right after auth so the UI paints immediately.
  async refreshNow() {
    await this.updatePlaybackInfo();
    await this.updateQueue();
  }

  // Slow safety-net poll (live updates do the heavy lifting via subscribeRealtime).
  startPeriodicUpdates() {
    if (this.updateInterval) {
      clearInterval(this.updateInterval);
    }

    this.updateInterval = setInterval(async () => {
      try {
        await this.updatePlaybackInfo();
        await this.updateQueue();
      } catch (error) {
        console.warn('Periodic update failed:', error.message);
      }
    }, 15000); // Fallback refresh every 15s
  }

  stopPeriodicUpdates() {
    if (this.updateInterval) {
      clearInterval(this.updateInterval);
      this.updateInterval = null;
    }
  }

  // Update playback information
  async updatePlaybackInfo() {
    try {
      const result = await this.apiService.getPlaybackInfo();
      if (result.success) {
        const playback = result.playback;
        this.state.setCurrentSong(
          playback.current_song,
          playback.position || 0,
          playback.is_playing || false
        );
      }
    } catch (error) {
      console.warn('Failed to update playback info:', error.message);
    }
  }

  // Update queue information
  async updateQueue() {
    try {
      const result = await this.apiService.getQueue();
      if (result.success) {
        this.state.setQueue(result.queue, result.total_count);
      }
    } catch (error) {
      // Don't surface a global error from the background poll — it would repaint
      // (and re-show) the error banner repeatedly. Just log it.
      console.warn('Failed to update queue:', error.message);
    }
  }

  // Search songs
  async searchSongs(query, page = 1) {
    console.log('🔍 GuestController searchSongs called with query:', query, 'page:', page);
    try {
      console.log('🔍 GuestController setting searchLoading=true and searchQuery=', query);
      this.state.setState({ searchLoading: true, searchQuery: query });
      
      console.log('🔍 GuestController calling apiService.searchSongs');
      const result = await this.apiService.searchSongs(query, page);
      console.log('🔍 GuestController search result:', result);
      
      if (result.success) {
        console.log('🔍 GuestController setting search results:', result.songs?.length || 0, 'songs');
        this.state.setSearchResults(result.songs, result.pagination, query);
      }
    } catch (error) {
      console.error('🔍 GuestController search failed:', error);
      this.state.setError('Search failed: ' + error.message);
    } finally {
      console.log('🔍 GuestController setting searchLoading=false');
      this.state.setState({ searchLoading: false });
    }
  }

  // Request a song
  async requestSong(songId) {
    try {
      this.state.setLoading(true);
      
      const result = await this.apiService.requestSong(songId);
      if (result.success) {
        // Refresh the queue to show the new request
        await this.updateQueue();
        
        // Show success message (could be handled by UI)
        console.log('Song requested successfully');
        return { success: true };
      }
    } catch (error) {
      console.error('Request failed:', error);
      this.state.setError('Failed to request song: ' + error.message);
      return { success: false, error: error.message };
    } finally {
      this.state.setLoading(false);
    }
  }

  // Promote a random queued song into the request queue
  async promoteSong(songId) {
    const result = await this.apiService.promoteSong(songId);
    if (result.success) {
      await this.updateQueue();
    } else {
      this.state.setError(result.message || 'Could not promote song');
    }
    return result;
  }

  // Update play history. reset=true reloads from page 1; reset=false appends
  // the next page (infinite scroll).
  async loadHistory(reset = true) {
    if (this.historyLoading) return;
    if (!reset && !this.historyHasMore) return;
    this.historyLoading = true;
    const page = reset ? 1 : this.historyPage + 1;
    try {
      const result = await this.apiService.getHistory(page, this.historyPerPage);
      if (result.success) {
        const items = result.history || [];
        this.historyItems = reset ? items : this.historyItems.concat(items);
        this.historyPage = page;
        this.historyHasMore = result.pagination ? !!result.pagination.has_more : false;
        this.state.setHistory(this.historyItems, this.historyHasMore);
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

  // Prepend newly-played songs without disturbing scroll / loaded pages.
  async refreshNewestHistory() {
    const result = await this.apiService.getHistory(1, this.historyPerPage);
    if (result.success) {
      const known = new Set(this.historyItems.map(h => h.id));
      const fresh = (result.history || []).filter(h => !known.has(h.id));
      if (fresh.length) {
        this.historyItems = fresh.concat(this.historyItems);
        this.state.setHistory(this.historyItems, this.historyHasMore);
      }
    }
  }

  // Navigation
  switchToNowPlaying() {
    this.state.setView('now-playing');
  }

  switchToRequestSongs() {
    this.state.setView('request-songs');
  }

  switchToHistory() {
    this.loadHistory();
    this.state.setView('play-history');
  }

  // Cleanup
  destroy() {
    this.stopPeriodicUpdates();
    if (this.cableSubscription) {
      this.cableSubscription.unsubscribe();
      this.cableSubscription = null;
    }
  }

  // Get current state
  getState() {
    return this.state.getState();
  }
}
