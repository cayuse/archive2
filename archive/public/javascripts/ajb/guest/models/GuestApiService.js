// Guest API Service - Handles communication with guest endpoints
class GuestApiService {
  constructor(jukeboxId, password = null) {
    this.jukeboxId = jukeboxId;
    this.password = password;
    this.baseUrl = `/api/v1/guest/${jukeboxId}`;
    this.authenticated = false;
  }

  // Build query string with password if needed
  buildQueryString() {
    const params = new URLSearchParams();
    if (this.password) {
      params.append('password', this.password);
    }
    return params.toString();
  }

  // Get jukebox status
  async getStatus() {
    try {
      const queryString = this.buildQueryString();
      const url = `${this.baseUrl}/status${queryString ? '?' + queryString : ''}`;
      
      const response = await fetch(url, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        },
        credentials: 'same-origin'
      });

      if (!response.ok) {
        if (response.status === 401) {
          throw new Error('Invalid password or jukebox access denied');
        } else if (response.status === 403) {
          throw new Error('Jukebox is not currently active');
        } else if (response.status === 404) {
          throw new Error('Jukebox not found');
        }
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }

      const data = await response.json();
      this.authenticated = true;
      return { success: true, jukebox: data.jukebox };
    } catch (error) {
      console.error('Error getting jukebox status:', error);
      throw error;
    }
  }

  // Get current song
  async getCurrentSong() {
    try {
      const queryString = this.buildQueryString();
      const url = `${this.baseUrl}/current_song${queryString ? '?' + queryString : ''}`;
      
      const response = await fetch(url, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        },
        credentials: 'same-origin'
      });

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }

      const data = await response.json();
      return { success: true, song: data.song, position: data.position, is_playing: data.is_playing };
    } catch (error) {
      console.error('Error getting current song:', error);
      throw error;
    }
  }

  // Get queue (upcoming songs)
  async getQueue() {
    try {
      const queryString = this.buildQueryString();
      const url = `${this.baseUrl}/queue${queryString ? '?' + queryString : ''}`;
      
      const response = await fetch(url, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        },
        credentials: 'same-origin'
      });

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }

      const data = await response.json();
      return { success: true, queue: data.queue, total_count: data.total_count };
    } catch (error) {
      console.error('Error getting queue:', error);
      throw error;
    }
  }

  // Get playback info (combined status)
  async getPlaybackInfo() {
    try {
      const queryString = this.buildQueryString();
      const url = `${this.baseUrl}/playback_info${queryString ? '?' + queryString : ''}`;
      
      const response = await fetch(url, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        },
        credentials: 'same-origin'
      });

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }

      const data = await response.json();
      return { success: true, playback: data.playback };
    } catch (error) {
      console.error('Error getting playback info:', error);
      throw error;
    }
  }

  // Search songs (using guest-specific search endpoint)
  async searchSongs(query, page = 1, perPage = 50) {
    try {
      const queryString = this.buildQueryString();
      const params = new URLSearchParams({
        q: query,
        page: page,
        per_page: perPage
      });
      
      if (queryString) {
        params.append('password', this.password);
      }
      
      const response = await fetch(`${this.baseUrl}/search_songs?${params}`, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        },
        credentials: 'same-origin'
      });

      if (!response.ok) {
        if (response.status === 401) {
          throw new Error('Invalid password or jukebox access denied');
        } else if (response.status === 403) {
          throw new Error('Jukebox is not currently active');
        } else if (response.status === 404) {
          throw new Error('Jukebox not found');
        }
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }

      const data = await response.json();
      return { success: true, songs: data.songs, pagination: data.pagination };
    } catch (error) {
      console.error('Error searching songs:', error);
      throw error;
    }
  }

  // Request a song (add to queue as "requested")
  async requestSong(songId) {
    try {
      const queryString = this.buildQueryString();
      const url = `${this.baseUrl}/request_song${queryString ? '?' + queryString : ''}`;
      
      const response = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        },
        credentials: 'same-origin',
        body: JSON.stringify({
          song_id: songId
        })
      });

      if (!response.ok) {
        if (response.status === 401) {
          throw new Error('Invalid password or jukebox access denied');
        } else if (response.status === 403) {
          throw new Error('Jukebox is not currently active');
        } else if (response.status === 404) {
          throw new Error('Song not found');
        } else if (response.status === 409) {
          throw new Error('Song is already in the queue');
        }
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }

      const data = await response.json();
      return { success: true, message: data.message || 'Song requested successfully', queue_item: data.queue_item };
    } catch (error) {
      console.error('Error requesting song:', error);
      throw error;
    }
  }
}
