// AJB PlaybackState - Manages player state
class PlaybackState {
  constructor() {
    this.currentSong = null;
    this.isPlaying = false;
    this.isPaused = false;
    this.isStopped = true;
    this.currentTime = 0;
    this.duration = 0;
    this.volume = 0.8;
    
    // Callbacks
    this.onStateChange = null;
    this.onSongChange = null;
    this.onTimeUpdate = null;
  }

  // Update the current song
  setCurrentSong(song) {
    this.currentSong = song;
    this.currentTime = 0;
    this.duration = song ? song.duration : 0;
    this.notifySongChange();
  }

  // Update playback status
  setPlaybackStatus(isPlaying, isPaused, isStopped) {
    this.isPlaying = isPlaying;
    this.isPaused = isPaused;
    this.isStopped = isStopped;
    this.notifyStateChange();
  }

  // Update time information
  updateTime(currentTime, duration) {
    this.currentTime = currentTime || 0;
    this.duration = duration || 0;
    this.notifyTimeUpdate();
    this.notifyStateChange(); // Also notify state change for server updates
  }

  // Set volume
  setVolume(volume) {
    this.volume = Math.max(0, Math.min(1, volume));
    this.notifyStateChange();
  }

  // Get current state
  getState() {
    return {
      currentSong: this.currentSong,
      isPlaying: this.isPlaying,
      isPaused: this.isPaused,
      isStopped: this.isStopped,
      currentTime: this.currentTime,
      duration: this.duration,
      volume: this.volume
    };
  }

  // Format time as MM:SS
  formatTime(seconds) {
    if (!seconds || isNaN(seconds)) return '0:00';
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  }

  // Get progress percentage (0-100)
  getProgressPercentage() {
    if (!this.duration || this.duration === 0) return 0;
    return Math.min(100, (this.currentTime / this.duration) * 100);
  }

  // Notify listeners
  notifyStateChange() {
    if (this.onStateChange) {
      this.onStateChange(this.getState());
    }
  }

  notifySongChange() {
    if (this.onSongChange) {
      this.onSongChange(this.currentSong);
    }
  }

  notifyTimeUpdate() {
    if (this.onTimeUpdate) {
      this.onTimeUpdate(this.currentTime, this.duration);
    }
  }
}