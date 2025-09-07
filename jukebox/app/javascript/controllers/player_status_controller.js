import { Controller } from "@hotwired/stimulus"

// data-controller="player-status"
// Optional data attributes to override endpoints:
// data-player-status-status-url-value
// data-player-status-upcoming-url-value

export default class extends Controller {
  static values = {
    statusUrl: { type: String, default: "/live/status" },
    upcomingUrl: { type: String, default: "/live/upcoming" }
  }

  connect() {
    // Expose a minimal API to global for existing onclick hooks
    window.playerStatusCtrl = this
    window.refreshUpcomingSongs = () => this.refreshUpcoming()
    window.moveSongToTop = (n) => this.moveSongToTop(n)
    window.removeSongFromQueue = (n) => this.removeSongFromQueue(n)

    this.errorCount = 0
    this.maxInterval = 30000
    this.baseStatusInterval = 1000
    this.baseUpcomingInterval = 10000
    this.statusDelay = this.baseStatusInterval
    this.upcomingDelay = this.baseUpcomingInterval
    this.running = true

    // Visibility/focus/online handlers
    this.visibilityHandler = () => this.onVisibilityChange()
    this.focusHandler = () => this.resumeNow()
    this.onlineHandler = () => this.resumeNow()
    document.addEventListener("visibilitychange", this.visibilityHandler)
    window.addEventListener("focus", this.focusHandler)
    window.addEventListener("online", this.onlineHandler)

    // Kick off loops
    this.tickStatus()
    this.tickUpcoming()
  }

  disconnect() {
    this.running = false
    document.removeEventListener("visibilitychange", this.visibilityHandler)
    window.removeEventListener("focus", this.focusHandler)
    window.removeEventListener("online", this.onlineHandler)
    if (this.statusTimer) clearTimeout(this.statusTimer)
    if (this.upcomingTimer) clearTimeout(this.upcomingTimer)
  }

  onVisibilityChange() {
    if (!document.hidden) this.resumeNow()
  }

  resumeNow() {
    if (!this.running) return
    if (this.statusTimer) clearTimeout(this.statusTimer)
    if (this.upcomingTimer) clearTimeout(this.upcomingTimer)
    this.statusDelay = this.baseStatusInterval
    this.upcomingDelay = this.baseUpcomingInterval
    this.tickStatus()
    this.tickUpcoming()
  }

  async tickStatus() {
    if (!this.running) return
    if (!document.hidden) await this.fetchStatus()
    this.statusTimer = setTimeout(() => this.tickStatus(), this.statusDelay)
  }

  async tickUpcoming() {
    if (!this.running) return
    if (!document.hidden) await this.fetchUpcoming()
    this.upcomingTimer = setTimeout(() => this.tickUpcoming(), this.upcomingDelay)
  }

  async fetchStatus() {
    const ok = await this.fetchJson(this.statusUrlValue, (data) => this.updateLiveDisplay(data))
    this.statusDelay = ok ? this.baseStatusInterval : Math.min(this.statusDelay * 2, this.maxInterval)
  }

  async fetchUpcoming() {
    const ok = await this.fetchJson(this.upcomingUrlValue, (data) => this.updateUpcomingDisplay(data.upcoming_songs, data.logged_in))
    this.upcomingDelay = ok ? this.baseUpcomingInterval : Math.min(this.upcomingDelay * 2, this.maxInterval)
  }

  async fetchJson(url, onData) {
    try {
      const controller = new AbortController()
      const t = setTimeout(() => controller.abort(), 8000)
      const res = await fetch(url, { headers: { "Accept": "application/json" }, cache: "no-store", signal: controller.signal })
      clearTimeout(t)
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const data = await res.json()
      onData?.(data)
      this.errorCount = 0
      return true
    } catch (e) {
      console.error("player-status fetch error:", e)
      this.errorCount += 1
      return false
    }
  }

  // Public method for refresh button
  refreshUpcoming() {
    this.fetchUpcoming()
  }

  // DOM updates (works for both live and system where IDs differ). We try live-* first, then fallback to system IDs.
  updateLiveDisplay(data) {
    const ps = data.player_status || data
    this.updateSongInfo(ps)
    this.updateProgress(ps)
  }

  q(id1, id2) {
    return document.getElementById(id1) || (id2 ? document.getElementById(id2) : null)
  }

  updateSongInfo(ps) {
    const container = this.q("live-song-info", "song-info")
    if (!container) return
    const title = ps?.song_title
    const artist = ps?.song_artist
    const album = ps?.song_album
    if (title) {
      container.innerHTML = `
        <div class="song-title theme-text-primary">${title}</div>
        ${artist ? `<div class="song-artist theme-text-secondary">${artist}</div>` : '<div class="song-artist theme-text-muted">Unknown Artist</div>'}
        ${album ? `<div class="song-album theme-text-muted">${album}</div>` : '<div class="song-album theme-text-muted">Unknown Album</div>'}
      `
    } else {
      container.innerHTML = `
        <div class="song-title theme-text-primary">No song playing</div>
        <div class="song-artist theme-text-secondary"></div>
        <div class="song-album theme-text-muted"></div>
      `
    }
  }

  updateProgress(ps) {
    const fill = this.q("live-progress-fill", "progress-fill")
    const elapsedEl = this.q("live-elapsed-time", "elapsed-time")
    const totalEl = this.q("live-total-time", "total-time")
    const remainEl = this.q("live-remaining-time", "remaining-time")
    if (!fill || !elapsedEl || !totalEl || !remainEl) return
    const elapsed = parseFloat(ps?.elapsed_seconds || 0)
    const duration = parseFloat(ps?.duration_seconds || 0)
    const progress = parseFloat(ps?.progress_percent || 0)
    fill.style.width = `${progress}%`
    elapsedEl.textContent = this.formatTime(elapsed)
    totalEl.textContent = this.formatTime(duration)
    remainEl.textContent = this.formatTime(duration - elapsed)
  }

  updateUpcomingDisplay(upcomingSongs = [], loggedIn = false) {
    const content = document.getElementById("upcoming-songs-content")
    const count = document.getElementById("upcoming-count")
    if (!content || !count) return
    count.textContent = `${upcomingSongs.length} songs`
    if (upcomingSongs.length === 0) {
      content.innerHTML = `
        <div class="text-center py-4">
          <i class="fas fa-list fa-3x text-muted mb-3"></i>
          <h5 class="text-muted">No upcoming songs</h5>
          <p class="text-muted">Add songs to the queue to see upcoming tracks</p>
        </div>
      `
      return
    }
    content.innerHTML = `
      <div class="table-responsive">
        <table class="table table-hover">
          <thead>
            <tr>
              <th style="width: 50px;">#</th>
              <th>Song</th>
              <th>Artist</th>
              <th>Album</th>
              <th style="width: 100px;">Duration</th>
              <th style="width: 80px;">Source</th>
              ${loggedIn ? '<th style="width: 80px;">Actions</th>' : ''}
            </tr>
          </thead>
          <tbody>
            ${upcomingSongs.map((item, index) => `
              <tr>
                <td><span class="badge bg-secondary">${index + 1}</span></td>
                <td><strong style="color: #1f2937;">${item.song.title}</strong></td>
                <td><span style="color: #1f2937;">${item.song.artist_name || 'Unknown Artist'}</span></td>
                <td><span style="color: #1f2937;">${item.song.album_name || 'Unknown Album'}</span></td>
                <td><span style="color: #1f2937;">${item.song.duration ? this.formatTime(item.song.duration) : '-'}</span></td>
                <td>
                  <span class="badge ${item.source === 'random' ? 'bg-success' : 'bg-info'}" title="Order #${item.order_number}">
                    ${item.source === 'random' ? 'Random' : 'Queue'}
                  </span>
                </td>
                ${loggedIn ? `
                  <td>
                    <div class="btn-group btn-group-sm" role="group">
                      <button type="button" class="btn btn-outline-primary btn-sm" onclick="playerStatusCtrl?.moveSongToTop(${item.order_number})" title="Move to top of queue">⬆️</button>
                      <button type="button" class="btn btn-outline-danger btn-sm" onclick="playerStatusCtrl?.removeSongFromQueue(${item.order_number})" title="Remove from queue">❌</button>
                    </div>
                  </td>
                ` : ''}
              </tr>
            `).join('')}
          </tbody>
        </table>
      </div>
    `
  }

  async moveSongToTop(orderNumber) {
    try {
      const res = await fetch('/songs/move_to_top', { method: 'POST', headers: this.jsonHeaders(), body: JSON.stringify({ order_number: orderNumber }) })
      const result = await res.json()
      if (result.success) this.fetchUpcoming()
    } catch (e) { console.error(e) }
  }

  async removeSongFromQueue(orderNumber) {
    if (!confirm('Are you sure you want to remove this song from the queue?')) return
    try {
      const res = await fetch('/songs/remove_from_queue', { method: 'POST', headers: this.jsonHeaders(), body: JSON.stringify({ order_number: orderNumber }) })
      const result = await res.json()
      if (result.success) this.fetchUpcoming()
    } catch (e) { console.error(e) }
  }

  jsonHeaders() {
    return {
      'Content-Type': 'application/json',
      'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.getAttribute('content')
    }
  }

  formatTime(seconds) {
    if (!seconds || seconds < 0 || isNaN(seconds)) return '0:00'
    const mins = Math.floor(seconds / 60)
    const secs = Math.floor(seconds % 60)
    return `${mins}:${secs.toString().padStart(2, '0')}`
  }
}

// Keep a handle for onclick buttons in the view
window.playerStatusCtrl = null
document.addEventListener("stimulus:load", () => {
  // Not all Stimulus versions dispatch this; alternatively set in connect
})

