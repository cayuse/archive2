import { createConsumer } from "@rails/actioncable"

const consumer = createConsumer()

// Player channel for real-time updates
const playerChannel = consumer.subscriptions.create("PlayerChannel", {
  connected() {
    console.log("Connected to PlayerChannel")
    this.requestStatus()
  },

  disconnected() {
    console.log("Disconnected from PlayerChannel")
  },

  received(data) {
    console.log("PlayerChannel received:", data)
    
    switch (data.type) {
      case 'status_update':
        this.updatePlayerStatus(data.data)
        break
      case 'command_result':
        this.handleCommandResult(data.data)
        break
      case 'error':
        this.handleError(data.message)
        break
      default:
        // Handle legacy format (direct status data)
        if (data.status || data.current_song) {
          this.updatePlayerStatus(data)
        }
    }
  },

  // Request current status
  requestStatus() {
    this.perform('status')
  },

  // Send player commands
  play() {
    this.perform('play')
  },

  pause() {
    this.perform('pause')
  },

  stop() {
    this.perform('stop')
  },

  next() {
    this.perform('next')
  },

  previous() {
    this.perform('previous')
  },

  setVolume(volume) {
    this.perform('volume', { volume: volume })
  },

  // Update the UI with player status
  updatePlayerStatus(status) {
    // Update current song display
    if (status.current_song) {
      const song = status.current_song
      this.updateElement('current-song-title', song.title || 'Unknown')
      this.updateElement('current-song-artist', song.artist || 'Unknown')
      this.updateElement('current-song-album', song.album || 'Unknown')
    } else {
      this.updateElement('current-song-title', 'No song playing')
      this.updateElement('current-song-artist', '')
      this.updateElement('current-song-album', '')
    }

    // Update player state
    this.updateElement('player-state', status.state || 'unknown')
    
    // Update progress bar
    if (status.progress !== undefined) {
      this.updateProgressBar(status.progress)
    }

    // Update volume display
    if (status.volume !== undefined) {
      this.updateVolumeDisplay(status.volume)
    }

    // Update queue length
    if (status.playlist_length !== undefined) {
      this.updateElement('queue-length', status.playlist_length)
    }

    // Update play/pause button state
    this.updatePlayButton(status.state === 'play')

    // Update time displays
    if (status.elapsed !== undefined) {
      this.updateElement('elapsed-time', this.formatTime(status.elapsed))
    }
    if (status.duration !== undefined) {
      this.updateElement('total-time', this.formatTime(status.duration))
    }

    // Trigger custom event for other components
    this.dispatchCustomEvent('playerStatusUpdated', status)
  },

  // Handle command results
  handleCommandResult(result) {
    if (result.success) {
      this.showNotification(result.message || 'Command executed successfully', 'success')
    } else {
      this.showNotification(result.error || 'Command failed', 'error')
    }
  },

  // Handle errors
  handleError(message) {
    this.showNotification(message, 'error')
  },

  // Helper methods
  updateElement(id, text) {
    const element = document.getElementById(id)
    if (element) {
      element.textContent = text
    }
  },

  updateProgressBar(progress) {
    const progressBar = document.getElementById('progress-bar')
    if (progressBar) {
      progressBar.style.width = `${progress}%`
      progressBar.setAttribute('aria-valuenow', progress)
    }
  },

  updateVolumeDisplay(volume) {
    const volumeSlider = document.getElementById('volume-slider')
    if (volumeSlider) {
      volumeSlider.value = volume
    }
    this.updateElement('volume-display', `${volume}%`)
  },

  updatePlayButton(isPlaying) {
    const playButton = document.getElementById('play-button')
    const pauseButton = document.getElementById('pause-button')
    
    if (playButton && pauseButton) {
      if (isPlaying) {
        playButton.style.display = 'none'
        pauseButton.style.display = 'inline-block'
      } else {
        playButton.style.display = 'inline-block'
        pauseButton.style.display = 'none'
      }
    }
  },

  formatTime(seconds) {
    const mins = Math.floor(seconds / 60)
    const secs = Math.floor(seconds % 60)
    return `${mins}:${secs.toString().padStart(2, '0')}`
  },

  showNotification(message, type = 'info') {
    // Create notification element
    const notification = document.createElement('div')
    notification.className = `notification notification-${type}`
    notification.textContent = message
    
    // Add to page
    document.body.appendChild(notification)
    
    // Remove after 3 seconds
    setTimeout(() => {
      if (notification.parentNode) {
        notification.parentNode.removeChild(notification)
      }
    }, 3000)
  },

  dispatchCustomEvent(eventName, data) {
    const event = new CustomEvent(eventName, { detail: data })
    document.dispatchEvent(event)
  }
})

// Export for use in other modules
export default playerChannel

// Global access for inline scripts
window.playerChannel = playerChannel
