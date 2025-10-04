// Guest Controller - Business logic for the guest interface
class GuestController {
  constructor(jukeboxId, password = null) {
    this.jukeboxId = jukeboxId;
    this.password = password;
    this.apiService = new GuestApiService(jukeboxId, password);
    this.state = new GuestState();
    this.updateInterval = null;
    
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

  // Authentication
  async authenticate() {
    try {
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
        
        // Start periodic updates
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

  // Start periodic updates for real-time data
  startPeriodicUpdates() {
    if (this.updateInterval) {
      clearInterval(this.updateInterval);
    }

    this.updateInterval = setInterval(async () => {
      try {
        await this.updatePlaybackInfo();
        await this.updateQueue(); // Also update queue periodically
      } catch (error) {
        console.warn('Periodic update failed:', error.message);
      }
    }, 2000); // Update every 2 seconds
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
      console.error('Failed to update queue:', error.message);
      this.state.setError('Failed to load queue');
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

  // Navigation
  switchToNowPlaying() {
    this.state.setView('now-playing');
  }

  switchToRequestSongs() {
    this.state.setView('request-songs');
  }

  // Cleanup
  destroy() {
    this.stopPeriodicUpdates();
  }

  // Get current state
  getState() {
    return this.state.getState();
  }
}
