// Guest Controller - Main business logic for the guest app
class GuestController {
  constructor(config) {
    this.config = config;
    this.webSocketService = new WebSocketService(config);
    this.apiService = new ApiService(config);
    this.isInitialized = false;
    this.syncInterval = null;
    this.currentPlaybackInfo = null;
    this.searchResults = [];
    this.queue = [];
  }

  // Initialize the controller
  async initialize() {
    if (this.isInitialized) return;

    try {
      console.log('Initializing Guest Controller...');

      // Connect WebSocket for real-time updates
      this.webSocketService.connect();

      // Set up event listeners
      this.setupEventListeners();

      // Start periodic sync for playback info
      this.startPeriodicSync();

      // Load initial state
      await this.loadInitialState();

      this.isInitialized = true;
      console.log('Guest Controller initialized successfully');

    } catch (error) {
      console.error('Failed to initialize Guest Controller:', error);
      throw error;
    }
  }

  // Set up event listeners
  setupEventListeners() {
    // WebSocket events for real-time updates
    this.webSocketService.addEventListener('playback_status_update', (data) => {
      this.currentPlaybackInfo = data;
      this.notifyListeners('playbackUpdate', data);
    });

    this.webSocketService.addEventListener('queue_updated', (data) => {
      this.queue = data.queue || [];
      this.notifyListeners('queueUpdate', this.queue);
    });

    this.webSocketService.addEventListener('current_song_updated', (data) => {
      this.currentPlaybackInfo = { ...this.currentPlaybackInfo, ...data };
      this.notifyListeners('currentSongUpdate', data);
    });

    // Connection status events
    this.webSocketService.addEventListener('connected', () => {
      this.notifyListeners('connectionStatus', 'connected');
    });

    this.webSocketService.addEventListener('disconnected', () => {
      this.notifyListeners('connectionStatus', 'disconnected');
    });
  }

  // Start periodic synchronization with server
  startPeriodicSync() {
    this.syncInterval = setInterval(async () => {
      try {
        await this.syncPlaybackInfo();
      } catch (error) {
        console.error('Sync with server failed:', error);
      }
    }, 2000); // Sync every 2 seconds for guests
  }

  // Load initial state from server
  async loadInitialState() {
    try {
      const [playbackInfo, queue] = await Promise.all([
        this.apiService.getPlaybackInfo(),
        this.apiService.getQueue()
      ]);

      this.currentPlaybackInfo = playbackInfo.playback_info;
      this.queue = queue.songs || [];

      console.log('Initial state loaded:', { playbackInfo, queue });
    } catch (error) {
      console.error('Failed to load initial state:', error);
    }
  }

  // Sync playback info from server
  async syncPlaybackInfo() {
    try {
      const playbackInfo = await this.apiService.getPlaybackInfo();
      this.currentPlaybackInfo = playbackInfo.playback_info;
      this.notifyListeners('playbackUpdate', this.currentPlaybackInfo);
    } catch (error) {
      console.error('Failed to sync playback info:', error);
    }
  }

  // Search for songs
  async searchSongs(query) {
    try {
      const results = await this.apiService.searchSongs(query);
      this.searchResults = results.songs || [];
      this.notifyListeners('searchResults', this.searchResults);
      return this.searchResults;
    } catch (error) {
      console.error('Failed to search songs:', error);
      this.searchResults = [];
      this.notifyListeners('searchResults', []);
      return [];
    }
  }

  // Request a song
  async requestSong(songId, requestedBy = 'Guest') {
    try {
      const result = await this.apiService.requestSong(songId, requestedBy);
      this.notifyListeners('songRequested', result);
      return result;
    } catch (error) {
      console.error('Failed to request song:', error);
      throw error;
    }
  }

  // Get current playback info
  getCurrentPlaybackInfo() {
    return this.currentPlaybackInfo;
  }

  // Get current queue
  getQueue() {
    return this.queue;
  }

  // Get search results
  getSearchResults() {
    return this.searchResults;
  }

  // Get connection status
  getConnectionStatus() {
    return this.webSocketService.getStatus();
  }

  // Event listener management
  addEventListener(eventType, callback) {
    if (!this.listeners) {
      this.listeners = new Map();
    }
    if (!this.listeners.has(eventType)) {
      this.listeners.set(eventType, []);
    }
    this.listeners.get(eventType).push(callback);
  }

  removeEventListener(eventType, callback) {
    if (this.listeners && this.listeners.has(eventType)) {
      const callbacks = this.listeners.get(eventType);
      const index = callbacks.indexOf(callback);
      if (index > -1) {
        callbacks.splice(index, 1);
      }
    }
  }

  notifyListeners(eventType, data) {
    if (this.listeners && this.listeners.has(eventType)) {
      this.listeners.get(eventType).forEach(callback => {
        try {
          callback(data);
        } catch (error) {
          console.error('Error in event listener:', error);
        }
      });
    }
  }

  // Cleanup
  destroy() {
    if (this.syncInterval) {
      clearInterval(this.syncInterval);
    }

    this.webSocketService.disconnect();
    this.listeners = new Map();
  }
}
