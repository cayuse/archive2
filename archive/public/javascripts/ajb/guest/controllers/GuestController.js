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
    // Hook for global state changes; nothing needed yet.
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
      if (result.offline) {
        this.handleOffline();
        return { success: false, offline: true };
      }
      if (result.success) {
        this.state.setAuthentication(this.jukeboxId, this.password);
        this.rememberCode(this.password);
        this.state.setState({
          role: result.jukebox.role === 'admin' ? 'admin' : 'guest',
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
        if (!this.onVisibilityChange) this.watchVisibility();

        return { success: true };
      }

      // Not success and not offline → bad code / not found / etc.
      this.state.setError(result.message || 'Could not join the jukebox');
      return { success: false };
    } catch (error) {
      this.state.setError(error.message);
      return { success: false, error: error.message };
    } finally {
      this.state.setLoading(false);
    }
  }

  // The join code is kept in this browser so a reload does not ask for it
  // again. Phones reload the page when they wake from sleep or return from
  // another app, which used to drop guests back at the join screen.
  storageKey() {
    return `ajb-guest-code:${this.jukeboxId}`;
  }

  storedCode() {
    try {
      return window.localStorage.getItem(this.storageKey());
    } catch (error) {
      return null; // storage blocked (private mode): fall back to asking
    }
  }

  rememberCode(code) {
    try {
      window.localStorage.setItem(this.storageKey(), code);
    } catch (error) { /* storage blocked: the code just won't survive a reload */ }
  }

  forgetCode() {
    try {
      window.localStorage.removeItem(this.storageKey());
    } catch (error) { /* nothing stored */ }
  }

  // Rejoin with the remembered code, if there is one. A code the host has
  // since changed is forgotten, and the join screen shows without an error.
  async resumeSession() {
    const code = this.storedCode();
    if (!code) return false;
    const result = await this.authenticate(code);
    if (!result.success && !result.offline) {
      this.forgetCode();
      this.state.clearError();
    }
    return !!result.success;
  }

  // Back to the join screen, e.g. to switch between the guest and admin code.
  leave() {
    this.forgetCode();
    this.destroy();
    this.password = null;
    this.apiService.password = null;
    this.state.setState({ authenticated: false, role: 'guest', currentView: 'now-playing', error: null });
  }

  // Timers and the socket are suspended while a phone sleeps, so catch up as
  // soon as the page is visible again instead of waiting for the next poll.
  watchVisibility() {
    this.onVisibilityChange = () => {
      if (document.visibilityState === 'visible' && this.state.getState().authenticated) {
        this.refreshNow();
      }
    };
    document.addEventListener('visibilitychange', this.onVisibilityChange);
  }

  // The jukebox went (or is) offline. Stop everything and reload, so the
  // server-rendered closed page (see _closed.html.erb) takes over — one closed
  // screen, in plain ERB, instead of a JS-rendered one with escaping/cache
  // pitfalls. On reload the server re-checks live? and shows the SPA again if
  // the host has restarted.
  handleOffline() {
    this.stopPeriodicUpdates();
    if (this.cableSubscription) {
      this.cableSubscription.unsubscribe();
      this.cableSubscription = null;
    }
    this.state.setOffline(true); // harmless; reload supersedes the in-app view
    window.location.reload();
  }

  // Subscribe to live jukebox updates over ActionCable. Now-playing changes and
  // queue changes are pushed instantly; the periodic poll below is only a
  // fallback for when the socket is unavailable or a message is missed.
  subscribeRealtime() {
    if (!this.jukeboxId || !(window.App && window.App.cable)) {
      console.warn('Live updates unavailable; relying on periodic polling.');
      return;
    }
    this.cableSubscription = window.App.cable.subscriptions.create(
      { channel: 'JukeboxChannel', jukebox_id: this.jukeboxId },
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
      if (result.offline) { this.handleOffline(); return; }
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
      if (result.offline) { this.handleOffline(); return; }
      if (result.success) {
        const lined = result.lined_up;
        this.state.setQueue((lined ? [{ source: 'lined_up', song: lined }] : []).concat(result.queue || []),
                            (result.total_count || 0) + (lined ? 1 : 0));
      }
    } catch (error) {
      // Don't surface a global error from the background poll — it would repaint
      // (and re-show) the error banner repeatedly. Just log it.
      console.warn('Failed to update queue:', error.message);
    }
  }

  // Search songs
  // page 1 replaces the results; later pages append ("Load more").
  async searchSongs(query, page = 1) {
    const requestId = (this.searchRequestId = (this.searchRequestId || 0) + 1);
    try {
      this.state.setState({ searchLoading: true, searchQuery: query });
      const result = await this.apiService.searchSongs(query, page);
      // A newer search started while this one was in flight: drop this result.
      if (requestId !== this.searchRequestId) return;
      if (result.success) {
        const songs = page > 1
          ? this.state.getState().searchResults.concat(result.songs)
          : result.songs;
        this.state.setSearchResults(songs, result.pagination, query);
      }
    } catch (error) {
      console.error('Search failed:', error);
      this.state.setError('Search failed: ' + error.message);
    } finally {
      if (requestId === this.searchRequestId) {
        this.state.setState({ searchLoading: false });
      }
    }
  }

  loadMoreSearchResults() {
    const { searchQuery, searchPagination, searchLoading } = this.state.getState();
    if (searchLoading || !searchPagination || !searchPagination.has_more) return;
    return this.searchSongs(searchQuery, searchPagination.current_page + 1);
  }

  clearSearch() {
    this.searchRequestId = (this.searchRequestId || 0) + 1;
    this.state.setState({ searchLoading: false });
    this.state.setSearchResults([], null, '');
  }

  // Short confirmation shown at the bottom of the screen, then cleared.
  showNotice(text) {
    clearTimeout(this.noticeTimeout);
    this.state.setState({ notice: text });
    this.noticeTimeout = setTimeout(() => this.state.setState({ notice: null }), 3000);
  }

  // Request a song. The server bumps it instead if it is already auto-queued.
  async requestSong(songId, title = 'Song') {
    try {
      const result = await this.apiService.requestSong(songId);
      if (result.success) {
        await this.updateQueue();
        const notices = {
          added: `Added “${title}” to the queue`,
          already_queued: `“${title}” is already in the queue`,
          bumped: `Bumped “${title}” up the queue`,
          already_requested: `“${title}” is already requested`,
          playing: `“${title}” is playing now`
        };
        this.showNotice(notices[result.outcome] || notices.added);
        return { success: true };
      }
    } catch (error) {
      console.error('Request failed:', error);
      this.state.setError('Failed to request song: ' + error.message);
      return { success: false, error: error.message };
    }
  }

  // Promote a random queued song into the request queue
  async promoteSong(songId, title = 'Song') {
    const result = await this.apiService.promoteSong(songId);
    if (result.success) {
      await this.updateQueue();
      this.showNotice(`Bumped “${title}” up the queue`);
    } else {
      this.state.setError(result.message || 'Could not promote song');
    }
    return result;
  }

  // Admin code only: take a song out of the queue.
  async removeSong(songId, title = 'Song') {
    const result = await this.apiService.removeSong(songId);
    if (result.success) {
      await this.updateQueue();
      this.showNotice(`Removed “${title}”`);
    } else {
      this.state.setError(result.message || 'Could not remove song');
    }
    return result;
  }

  // Admin code only: play, pause or skip on the host's player. The new state
  // comes back through the normal playback updates.
  async sendPlayerCommand(command) {
    const result = await this.apiService.playerCommand(command);
    if (!result.success) {
      this.state.setError(result.message || 'Could not reach the player');
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
        if (reset) {
          this.historyItems = items;
        } else {
          const known = new Set(this.historyItems.map(h => h.id));
          this.historyItems = this.historyItems.concat(items.filter(h => !known.has(h.id)));
        }
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
    if (this.onVisibilityChange) {
      document.removeEventListener('visibilitychange', this.onVisibilityChange);
      this.onVisibilityChange = null;
    }
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
