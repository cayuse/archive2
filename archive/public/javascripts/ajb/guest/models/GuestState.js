// Guest State Management
class GuestState {
  constructor() {
    this.state = {
      // Authentication
      authenticated: false,
      jukeboxId: null,
      password: null,
      
      // Current playback
      currentSong: null,
      currentPosition: 0,
      isPlaying: false,
      volume: 0.8,
      
      // Queue
      queue: [],
      totalQueueCount: 0,
      
      // Search
      searchResults: [],
      searchQuery: '',
      searchLoading: false,
      searchPagination: null,
      
      // UI State
      currentView: 'now-playing', // 'now-playing' or 'request-songs'
      loading: false,
      error: null,
      
      // Jukebox info
      jukeboxName: '',
      jukeboxStatus: 'inactive'
    };
    this.listeners = [];
  }

  getState() {
    return { ...this.state };
  }

  setState(newState) {
    console.log('🔍 GuestState setState called with:', newState);
    this.state = { ...this.state, ...newState };
    console.log('🔍 GuestState new state after update:', this.state);
    this.notifyListeners();
  }

  subscribe(listener) {
    this.listeners.push(listener);
    return () => {
      this.listeners = this.listeners.filter(l => l !== listener);
    };
  }

  notifyListeners() {
    console.log('🔍 GuestState notifyListeners called with', this.listeners.length, 'listeners');
    this.listeners.forEach((listener, index) => {
      console.log('🔍 GuestState notifying listener', index, 'with state:', this.getState());
      listener(this.getState());
    });
  }

  // Helper methods
  setAuthentication(jukeboxId, password) {
    this.setState({ jukeboxId, password, authenticated: true });
  }

  setCurrentSong(song, position, isPlaying) {
    this.setState({ 
      currentSong: song, 
      currentPosition: position, 
      isPlaying: isPlaying 
    });
  }

  setQueue(queue, totalCount) {
    this.setState({ queue, totalQueueCount: totalCount });
  }

  setSearchResults(results, pagination, query) {
    console.log('🔍 GuestState setSearchResults called with:', {
      resultsLength: results?.length || 0,
      pagination: pagination,
      query: query
    });
    this.setState({ 
      searchResults: results, 
      searchPagination: pagination, 
      searchQuery: query 
    });
  }

  setView(view) {
    this.setState({ currentView: view });
  }

  setLoading(loading) {
    this.setState({ loading });
  }

  setError(error) {
    this.setState({ error });
  }

  clearError() {
    this.setState({ error: null });
  }

  // Time formatting helper
  static formatTime(seconds) {
    if (isNaN(seconds) || seconds === 0) return '0:00';
    const minutes = Math.floor(seconds / 60);
    const remainingSeconds = Math.floor(seconds % 60);
    return `${minutes}:${remainingSeconds < 10 ? '0' : ''}${remainingSeconds}`;
  }

  // Progress calculation
  getProgress() {
    const { currentSong, currentPosition } = this.state;
    if (!currentSong || !currentSong.duration) return 0;
    return Math.min((currentPosition / currentSong.duration) * 100, 100);
  }

  // Time remaining calculation
  getTimeRemaining() {
    const { currentSong, currentPosition } = this.state;
    if (!currentSong || !currentSong.duration) return 0;
    return Math.max(currentSong.duration - currentPosition, 0);
  }
}
