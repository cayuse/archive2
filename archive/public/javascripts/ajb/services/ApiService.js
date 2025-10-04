// AJB ApiService - Handles API communication
class ApiService {
  constructor(jukeboxId, apiToken) {
    console.log('🔍 ApiService constructor called with:', { jukeboxId, apiTokenLength: apiToken?.length });
    this.jukeboxId = jukeboxId;
    this.apiToken = apiToken;
    this.baseUrl = `/api/v1/jukeboxes/${jukeboxId}`;
    console.log('🔍 ApiService baseUrl:', this.baseUrl);
  }

  // Get next song from queue
  async getNextSong() {
    try {
      const response = await fetch(`${this.baseUrl}/next_song`, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
          'X-Requested-With': 'XMLHttpRequest',
          'Authorization': `Bearer ${this.apiToken}`
        },
        credentials: 'same-origin'
      });

      if (!response.ok) {
        if (response.status === 204) {
          return { success: false, message: 'No songs available' };
        }
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }

      const data = await response.json();
      return data;
    } catch (error) {
      console.error('Error getting next song:', error);
      return { success: false, message: error.message };
    }
  }

  // Get current queue status
  async getQueue() {
    try {
      const response = await fetch(`${this.baseUrl}/queue`, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
          'X-Requested-With': 'XMLHttpRequest',
          'Authorization': `Bearer ${this.apiToken}`
        },
        credentials: 'same-origin'
      });

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }

      const data = await response.json();
      return data;
    } catch (error) {
      console.error('Error getting queue:', error);
      return { success: false, message: error.message };
    }
  }

  // Get jukebox status
  async getStatus() {
    try {
      const response = await fetch(`${this.baseUrl}/status`, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
          'X-Requested-With': 'XMLHttpRequest',
          'Authorization': `Bearer ${this.apiToken}`
        },
        credentials: 'same-origin'
      });

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }

      const data = await response.json();
      return data;
    } catch (error) {
      console.error('Error getting status:', error);
      return { success: false, message: error.message };
    }
  }

  // Update playback status
  async updatePlaybackStatus(status) {
    try {
      const response = await fetch(`${this.baseUrl}/playback_status`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Requested-With': 'XMLHttpRequest',
          'Authorization': `Bearer ${this.apiToken}`
        },
        credentials: 'same-origin',
        body: JSON.stringify(status)
      });

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }

      const data = await response.json();
      return data;
    } catch (error) {
      console.error('Error updating playback status:', error);
      return { success: false, message: error.message };
    }
  }
}