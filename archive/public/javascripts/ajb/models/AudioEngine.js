// AJB AudioEngine: plays the jukebox in this browser through ONE <audio> element, for the whole
// session.
//
// Why one element, and why it never "ends" (learned on a locked iPhone, 2026-11-26; the
// diagnostics are in log/player_diagnostics.log):
//   * iOS lets a page play audio without a tap only on an element that was started by a tap. The
//     element keeps that right for as long as the page lives, so every song goes through it: a new
//     song is a new src on the same element. (Howler, used before, gave each song its own element;
//     on a locked phone iOS refused to start the second one, every time.)
//   * iOS ends the page's background audio session when a track reaches its natural 'ended'. So
//     the element loops (loop = true) and the next song is swapped in from 'timeupdate' just before
//     the end, inside the media event, not from a timer (iOS freezes timers on a locked phone).
//   * iOS does not buffer an element ahead. So the next song is downloaded whole with fetch() while
//     the current one plays, and handed to the element as a blob: it starts at once.
//   * If no next song is ready when this one ends, the element keeps looping, muted, so the session
//     stays alive while the next song is fetched.
//
// Howler (and its crossfading plans, see docs/history/ajb_design.md) is no longer used here.

// How songs are handed over, chosen from the page address (?ajb=...) so variants can be tried on a
// phone without a new release, and reported with every diagnostic:
//   ended | loop     swap when the element fires 'ended' (default), or loop and swap from
//                    'timeupdate' just before the end
//   stream | blob    give the element the song's URL (default), or a copy downloaded ahead
//   nopause | pause  change the src directly (default), or pause the element first
// iPhone, locked, 2026-11-26: loop + blob + pause swapped on time but the new song never moved off
// 0:00 (iOS said "playing", fully buffered).
const AJB_OPTS = (() => {
  const words = new Set(((typeof location !== 'undefined' && new URLSearchParams(location.search).get('ajb')) || '').split(/[\s,]+/).filter(Boolean));
  return { trigger: words.has('loop') ? 'loop' : 'ended', source: words.has('blob') ? 'blob' : 'stream', pause: words.has('pause') };
})();

const SILENT_WAV = 'data:audio/wav;base64,UklGRigAAABXQVZFZm10IBIAAAABAAEARKwAAIhYAQACABAAAABkYXRhAgAAAAEA';
const END_LEAD = 0.35;   // seconds before the end at which the next song is swapped in

class AudioEngine {
  constructor() {
    this.audio = document.createElement('audio');
    this.audio.preload = 'auto';
    this.audio.loop = AJB_OPTS.trigger === 'loop';
    this.audio.setAttribute('playsinline', '');
    this.audio.setAttribute('webkit-playsinline', '');
    this.audio.style.display = 'none';
    (document.body || document.documentElement).appendChild(this.audio);

    this.currentSong = null;
    this.next = null;              // { song, url, objectUrl, bytes, failed, abort } or null
    this.objectUrl = null;         // blob URL of the song in the element, revoked when replaced
    this.isPlaying = false;
    this.isPaused = false;
    this.isStopped = true;
    this.currentVolume = 0.8;
    this.audio.volume = this.currentVolume;   // (iOS ignores it: the hardware buttons rule)

    this._wantPlaying = false;
    this._ending = false;          // the end of this song has been signalled; waiting for the next
    this._lastTime = 0;
    this._unlocked = false;
    this._playWatchdog = null;
    this._playRetries = 0;
    this._lastProgressPos = null;
    this._progressStallTicks = 0;
    this._progressRecoveries = 0;
    this.onDiag = null;

    const a = this.audio;
    a.addEventListener('playing', () => {
      if (!this.currentSong || this._ending) return;
      this.isPlaying = true; this.isPaused = false; this.isStopped = false;
      this._playRetries = 0;
      this._clearPlayWatchdog();
      this.setMediaSessionPlaybackState('playing');
      // WebKit can drop the page's lock-screen actions when the element's src changes (every song):
      // register them again each time playback starts.
      this.setupMediaSession();
      if (this.onPlay) this.onPlay();
    });
    a.addEventListener('pause', () => {
      // a pause we did not ask for (swapping songs, an interruption) is not the host pausing
      if (this._wantPlaying || !this.currentSong) return;
      this.isPlaying = false; this.isPaused = true;
      this.setMediaSessionPlaybackState('paused');
      if (this.onPause) this.onPause();
    });
    a.addEventListener('timeupdate', () => { if (AJB_OPTS.trigger === 'loop') this._watchEnd(); });
    a.addEventListener('ended', () => {
      if (AJB_OPTS.trigger === 'ended' && this.currentSong && !this._ending && this._wantPlaying) this._songOver();
    });
    a.addEventListener('error', () => {
      if (!this.currentSong || !a.error) return;
      console.error('Audio error:', a.error);
      this._emitDiag('media_error');
      this.isPlaying = false; this.isStopped = true;
      this.setMediaSessionPlaybackState('none');
      if (this.onError) this.onError(a.error);
    });

    // The first tap anywhere on the page grants the element its right to play (see above).
    this._unlockOnTap = () => this.unlock();
    ['touchend', 'click', 'keydown'].forEach((e) => document.addEventListener(e, this._unlockOnTap, true));

    this.setupMediaSession();
    // Tell Safari this is media playback (Audio Session API, iOS 16.4+): it then keeps playing with
    // the screen locked and the ring switch on silent. Ignored where unsupported.
    try {
      if (navigator.audioSession && navigator.audioSession.type !== 'playback') navigator.audioSession.type = 'playback';
    } catch (e) { /* not supported */ }
  }

  // Must run inside a tap. Starts the element on a moment of silence so iOS lets it play later
  // without one; does nothing once the element has played.
  unlock() {
    if (this._unlocked) return;
    this._unlocked = true;
    ['touchend', 'click', 'keydown'].forEach((e) => document.removeEventListener(e, this._unlockOnTap, true));
    if (this.currentSong) return;   // a real song is already in the element
    try {
      this.audio.src = SILENT_WAV;
      const p = this.audio.play();
      if (p && p.catch) p.catch(() => {});
    } catch (e) { /* the real play() will try again */ }
  }

  // --- Songs in and out of the one element -------------------------------

  _use(song, url, objectUrl, startAt = 0) {
    const a = this.audio;
    this._ending = false;
    this._lastTime = 0;
    this._lastProgressPos = null;
    this._progressStallTicks = 0;
    this._clearPlayWatchdog();
    this.currentSong = song;
    this._wantPlaying = true;
    if (AJB_OPTS.pause) { try { a.pause(); } catch (e) { /* not playing */ } }
    a.src = url;
    a.muted = false;
    if (this.objectUrl && this.objectUrl !== objectUrl) URL.revokeObjectURL(this.objectUrl);
    this.objectUrl = objectUrl;
    if (startAt > 0) {
      const seek = () => { try { a.currentTime = startAt; } catch (e) { /* ignore */ } };
      a.readyState >= 1 ? seek() : a.addEventListener('loadedmetadata', seek, { once: true });
    }
    this.updateMediaSessionMetadata(song);
    this._play();
  }

  _play() {
    this._wantPlaying = true;
    let p;
    try { p = this.audio.play(); } catch (e) { p = Promise.reject(e); }
    if (p && typeof p.catch === 'function') {
      p.catch((e) => {
        if (e && e.name === 'AbortError') return;   // replaced by a newer src: not a failure
        console.warn('Audio: play refused', e);
        this._emitDiag('play_blocked');
        this._armPlayWatchdog();
      });
    }
    this._armPlayWatchdog();
  }

  // Called on every 'timeupdate': near the end (or if the loop has already jumped back to 0:00),
  // tell the controller the song is over. It answers synchronously with playPreloaded().
  _watchEnd() {
    const a = this.audio;
    const t = a.currentTime, dur = a.duration;
    const last = this._lastTime;
    this._lastTime = t;
    if (!this.currentSong || this._ending || !this._wantPlaying || !isFinite(dur) || dur <= 0) return;
    const nearEnd = dur - t <= END_LEAD;
    const wrapped = last > dur - 2 && t < last - 1;
    if (nearEnd || wrapped) this._songOver();
  }

  _songOver() {
    this._ending = true;
    if (AJB_OPTS.trigger === 'loop') this.audio.muted = true;   // keep it looping, silently, until the next song is in
    this.isPlaying = false; this.isPaused = false; this.isStopped = true;
    console.log('Audio: Ended');
    if (this.onEnd) this.onEnd();
  }

  // Load and play a song (the first one, a resume, a reload, or a song fetched at the end).
  async loadAndPlay(song, startAt = 0) {
    try {
      this._use(song, song.stream_url || song.download_url, null, startAt);
      return true;
    } catch (error) {
      console.error('Failed to load and play song:', error);
      return false;
    }
  }

  // --- The next song, downloaded ahead -----------------------------------

  preload(song) {
    if (!song) return;
    if (this.next && this.next.song.id === song.id) return;
    this.dropPreloaded();
    const ctrl = typeof AbortController !== 'undefined' ? new AbortController() : null;
    const next = { song: song, url: song.stream_url || song.download_url, objectUrl: null, bytes: 0, failed: false,
                   abort: () => { try { ctrl && ctrl.abort(); } catch (e) { /* done */ } } };
    this.next = next;
    this._emitDiag('preload');
    if (AJB_OPTS.source !== 'blob' || this.downloadAhead === false) return;   // streamed when its turn comes
    fetch(next.url, { credentials: 'same-origin', signal: ctrl ? ctrl.signal : undefined })
      .then((r) => { if (!r.ok) throw new Error('HTTP ' + r.status); return r.blob(); })
      .then((blob) => {
        if (this.next !== next) return;
        next.bytes = blob.size;
        next.objectUrl = URL.createObjectURL(blob);
        this._emitDiag('preloaded');
      })
      .catch((e) => {
        if (this.next !== next || (e && e.name === 'AbortError')) return;
        next.failed = true;
        console.warn('Audio: downloading the next song ahead failed; it will stream instead', e);
        this._emitDiag('preload_error');
      });
  }

  hasPreloaded() { return !!this.next; }
  preloadedSong() { return this.next ? this.next.song : null; }

  // The next song, now: from the downloaded copy if it is complete, else streamed. Runs inside the
  // media event that signalled the end. Returns the song, or null when nothing was lined up.
  playPreloaded() {
    if (!this.next) return null;
    const next = this.next;
    this.next = null;
    if (!next.objectUrl) next.abort();
    this._use(next.song, next.objectUrl || next.url, next.objectUrl, 0);
    return next.song;
  }

  dropPreloaded() {
    if (!this.next) return;
    this.next.abort();
    if (this.next.objectUrl) URL.revokeObjectURL(this.next.objectUrl);
    this.next = null;
  }

  // --- Transport -----------------------------------------------------------

  play() {
    if (!this.currentSong || this.isPlaying) return;
    this._playRetries = 0;
    this.audio.muted = false;
    this._play();
  }

  pause() {
    if (!this.currentSong) return;
    this._wantPlaying = false;
    this._clearPlayWatchdog();
    this.audio.pause();
  }

  stop() {
    this._wantPlaying = false;
    this._clearPlayWatchdog();
    try { this.audio.pause(); } catch (e) { /* nothing playing */ }
    const wasStopped = this.isStopped && !this.isPaused;
    this.isPlaying = false; this.isPaused = false; this.isStopped = true;
    this.setMediaSessionPlaybackState('none');
    if (!wasStopped && this.onStop) this.onStop();
  }

  restart() {
    if (!this.currentSong) return;
    this.seek(0);
    if (this.isStopped) this.play();
  }

  skip() {
    this.stop();
    if (this.onSkip) this.onSkip();
  }

  seek(seconds) {
    try { this.audio.currentTime = Math.max(0, seconds); } catch (e) { /* not loaded yet */ }
  }

  setVolume(volume) {
    this.currentVolume = Math.max(0, Math.min(1, volume));
    this.audio.volume = this.currentVolume;
  }

  getVolume() { return this.currentVolume; }
  getCurrentTime() { return this.currentSong ? (this.audio.currentTime || 0) : 0; }
  getDuration() { const d = this.audio.duration; return this.currentSong && isFinite(d) ? d : 0; }

  getPlaybackInfo() {
    return { currentSong: this.currentSong, currentTime: this.getCurrentTime(), duration: this.getDuration(),
             isPlaying: this.isPlaying, isPaused: this.isPaused, isStopped: this.isStopped };
  }

  // --- Stall recovery --------------------------------------------------------

  // After asking to play, confirm it started; retry a few times if the browser held it back.
  _armPlayWatchdog() {
    this._clearPlayWatchdog();
    this._playWatchdog = setTimeout(() => {
      this._playWatchdog = null;
      if (!this._wantPlaying || this.isPlaying || !this.currentSong || this._ending) return;
      if (this._playRetries >= 8) {
        console.warn('Audio: still stalled after retries; waiting for a tap or the page to come back');
        this._emitDiag('play_giveup');
        return;
      }
      this._playRetries += 1;
      this._play();
    }, 2500);
  }

  _clearPlayWatchdog() {
    if (this._playWatchdog) { clearTimeout(this._playWatchdog); this._playWatchdog = null; }
  }

  // The page came back (unlocked phone, refocused tab): if playback should be going but is not, kick it.
  nudgeIfStalled() {
    if (this._wantPlaying && this.currentSong && !this.isPlaying && !this._ending) {
      this._emitDiag('nudge');
      this._playRetries = 0;
      this._play();
    }
  }

  // "Playing" but the position does not move: reload the song where it was; after three tries,
  // move on. Called once a second by the controller.
  checkProgress() {
    if (!this._wantPlaying || !this.isPlaying || !this.currentSong || this._ending) {
      this._lastProgressPos = null;
      this._progressStallTicks = 0;
      return;
    }
    const pos = this.getCurrentTime();
    if (this._lastProgressPos !== null && Math.abs(pos - this._lastProgressPos) < 0.05) {
      this._progressStallTicks += 1;
      if (this._progressStallTicks >= 4) {
        this._progressStallTicks = 0;
        if (this._progressRecoveries < 3) {
          this._progressRecoveries += 1;
          this._emitDiag('stall_reload');
          // a downloaded copy that will not play is replaced by the stream (the copy is the suspect)
          const fromCopy = (this.audio.src || '').startsWith('blob:');
          const url = fromCopy ? (this.currentSong.stream_url || this.currentSong.download_url) : (this.audio.currentSrc || this.audio.src);
          this._use(this.currentSong, url, fromCopy ? null : this.objectUrl, pos);
        } else {
          this._emitDiag('stall_skip');
          this._progressRecoveries = 0;
          this._songOver();
        }
      }
    } else {
      this._progressStallTicks = 0;
      this._progressRecoveries = 0;
    }
    this._lastProgressPos = pos;
  }

  // --- Diagnostics (shipped with the heartbeat; read back from log/player_diagnostics.log) ---

  getDiagnostics() {
    const r = (n) => (typeof n === 'number' && isFinite(n)) ? Math.round(n * 100) / 100 : null;
    const a = this.audio;
    const pos = this.getCurrentTime(), dur = this.getDuration();
    const d = {
      build: (typeof window !== 'undefined' && window.AJB_BUILD) || null,
      engine: 'one-element',
      opts: AJB_OPTS.trigger + ',' + AJB_OPTS.source + (AJB_OPTS.pause ? ',pause' : ''),
      want: this._wantPlaying, playing: this.isPlaying, paused: this.isPaused, stopped: this.isStopped,
      ending: this._ending, retries: this._playRetries, stallTicks: this._progressStallTicks,
      recoveries: this._progressRecoveries, pos: r(pos), dur: r(dur),
      remaining: dur > 0 ? r(dur - pos) : null
    };
    try {
      d.ready = a.readyState; d.net = a.networkState; d.nodePaused = a.paused; d.muted = a.muted;
      d.src = !a.src ? null : (a.src.startsWith('blob:') ? 'blob' : (a.src.startsWith('data:') ? 'silence' : 'stream'));
      if (a.buffered && a.buffered.length) {
        const end = a.buffered.end(a.buffered.length - 1);
        d.bufAhead = r(end - pos);
      } else {
        d.bufAhead = 0;
      }
      if (this.next) d.next = { id: this.next.song.id, downloaded: !!this.next.objectUrl, bytes: this.next.bytes, failed: this.next.failed };
      if (typeof document !== 'undefined') d.vis = document.visibilityState;
      if (navigator.audioSession) d.session = navigator.audioSession.type;
    } catch (e) {
      d.err = String((e && e.message) || e);
    }
    return d;
  }

  _emitDiag(event) {
    if (this.onDiag) {
      try { this.onDiag(event); } catch (e) { /* diagnostics must never break playback */ }
    }
  }

  // --- MediaSession (OS lock-screen / background-audio integration) ---

  // Register the OS media-key / lock-screen action handlers once. These let the
  // user control playback from the lock screen or control center, and signal to
  // iOS/Android that this is an audio app that should keep running in the
  // background.
  setupMediaSession() {
    if (!('mediaSession' in navigator)) return;

    const set = (action, handler) => {
      try {
        navigator.mediaSession.setActionHandler(action, handler);
      } catch (e) {
        // Some browsers don't support every action; ignore the unsupported ones.
      }
    };

    set('play', () => this.play());
    set('pause', () => this.pause());
    set('stop', () => this.stop());
    set('nexttrack', () => this.skip());
    set('previoustrack', () => this.restart());
    // iOS draws "back 10 s / ahead 10 s" instead of previous / next track unless the seek actions
    // are explicitly switched off.
    set('seekbackward', null);
    set('seekforward', null);
  }

  // Push the current track's info to the lock screen.
  updateMediaSessionMetadata(song) {
    if (!('mediaSession' in navigator) || !song) return;
    try {
      navigator.mediaSession.metadata = new MediaMetadata({
        title: song.title || 'Unknown Title',
        artist: song.artist || 'Unknown Artist',
        album: song.album || ''
      });
    } catch (e) {
      console.warn('MediaSession metadata update failed:', e);
    }
  }

  setMediaSessionPlaybackState(state) {
    if (!('mediaSession' in navigator)) return;
    try {
      navigator.mediaSession.playbackState = state; // 'playing' | 'paused' | 'none'
    } catch (e) {
      // Non-critical.
    }
  }

  // Feed the lock-screen scrubber the current position. Called from the time loop.
  updateMediaSessionPosition() {
    if (!('mediaSession' in navigator) || typeof navigator.mediaSession.setPositionState !== 'function') return;
    const duration = this.getDuration();
    if (!duration || !isFinite(duration)) return;
    try {
      navigator.mediaSession.setPositionState({
        duration: duration,
        position: Math.min(this.getCurrentTime(), duration),
        playbackRate: 1
      });
    } catch (e) {
      // Non-critical.
    }
  }

  destroy() {
    this._wantPlaying = false;
    this._clearPlayWatchdog();
    this.dropPreloaded();
    try { this.audio.pause(); this.audio.removeAttribute('src'); this.audio.load(); } catch (e) { /* gone */ }
    if (this.objectUrl) { URL.revokeObjectURL(this.objectUrl); this.objectUrl = null; }
    this.currentSong = null;
  }
}
