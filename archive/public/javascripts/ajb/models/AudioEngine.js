// AJB AudioEngine - Howler.js based audio player
class AudioEngine {
  constructor() {
    this.sound = null;
    this.currentSong = null;
    this.isPlaying = false;
    this.isPaused = false;
    this.isStopped = true;
    this.currentVolume = 0.8; // Persistent volume setting (default 80%)

    // Stall recovery. On iOS Safari a play() issued while the screen is locked
    // (e.g. the moment a track auto-advances) can be silently deferred: the
    // <audio> loads but never starts, so position sits at 0 forever. We track
    // whether we *intend* to be playing and use a watchdog + unlock/visibility
    // retries to recover without the host having to manually stop/start.
    this._wantPlaying = false;
    this._playWatchdog = null;
    this._playRetries = 0;

    // Progress watchdog state. Separate from the play() watchdog: this catches
    // the case where Howler reports "playing" (onplay fired) but the <audio>
    // element's currentTime never advances — position pinned while is_playing
    // stays true. Recovered by reloading the track.
    this._lastProgressPos = null;
    this._progressStallTicks = 0;
    this._progressRecoveries = 0;

    // Optional hook: the controller sets this to pipe internal recovery events
    // (play blocked, stall reload/skip, nudge) straight into the diagnostic
    // heartbeat, so they're visible in the server log even on a locked phone.
    this.onDiag = null;

    // Initialize Howler
    if (typeof Howl === 'undefined') {
      throw new Error('Howler.js is required but not loaded');
    }

    // Wire up OS-level media controls (lock screen / control center) so playback
    // is treated as a background-audio session and keeps going when the screen
    // sleeps. Handlers are registered once and reused for every track.
    this.setupMediaSession();
  }

  // Load and play a song
  async loadAndPlay(song) {
    try {
      this.currentSong = song;
      this._wantPlaying = true;
      this._playRetries = 0;
      this._clearPlayWatchdog();
      // Reset progress tracking for the new (or reloaded) track. _progressRecoveries
      // is intentionally NOT reset here — it's cleared once playback actually
      // advances (in checkProgress), so reload attempts on the same stuck track
      // are counted and can escalate to a skip.
      this._lastProgressPos = null;
      this._progressStallTicks = 0;

      // Clean up previous sound
      if (this.sound) {
        this.sound.unload();
      }

      // Create new Howl instance.
      // html5: true forces playback through an HTML5 <audio> element instead of
      // the Web Audio API. iOS/iPadOS suspends the Web Audio context when the
      // screen locks (killing playback), but allows an <audio> element to keep
      // playing in the background — so this is what lets the jukebox survive a
      // sleeping phone/tablet. Prefer the Range-capable stream endpoint.
      this.sound = new Howl({
        src: [song.stream_url || song.download_url],
        format: ['mp3', 'm4a', 'ogg'],
        html5: true,
        volume: this.currentVolume, // Apply persistent volume setting
        onload: () => {
          console.log('Audio: Loaded successfully');
        },
        onplay: () => {
          this.isPlaying = true;
          this.isPaused = false;
          this.isStopped = false;
          this._playRetries = 0;
          this._clearPlayWatchdog();
          this.setMediaSessionPlaybackState('playing');
          console.log('Audio: Started playing');
          if (this.onPlay) this.onPlay();
        },
        onpause: () => {
          this.isPlaying = false;
          this.isPaused = true;
          this.setMediaSessionPlaybackState('paused');
          console.log('Audio: Paused');
          if (this.onPause) this.onPause();
        },
        onstop: () => {
          this.isPlaying = false;
          this.isPaused = false;
          this.isStopped = true;
          this.setMediaSessionPlaybackState('none');
          console.log('Audio: Stopped');
          if (this.onStop) this.onStop();
        },
        onend: () => {
          this.isPlaying = false;
          this.isPaused = false;
          this.isStopped = true;
          console.log('Audio: Ended');
          if (this.onEnd) this.onEnd();
        },
        onerror: (id, error) => {
          console.error('Audio error:', error);
          this.isPlaying = false;
          this.isPaused = false;
          this.isStopped = true;
          this.setMediaSessionPlaybackState('none');
          if (this.onError) this.onError(error);
        },
        onplayerror: (id, error) => {
          // The <audio> element couldn't start — almost always a locked audio
          // context on iOS (screen asleep when the track auto-advanced).
          // Resume on the first unlock, and let the watchdog keep retrying.
          console.warn('Audio: play blocked, will retry on unlock', error);
          this._emitDiag('play_blocked');
          if (this.sound) {
            this.sound.once('unlock', () => {
              if (this._wantPlaying && !this.isPlaying && this.sound) {
                try { this.sound.play(); } catch (e) {}
              }
            });
          }
          this._armPlayWatchdog();
        }
      });

      // Surface the track on the OS lock screen / control center.
      this.updateMediaSessionMetadata(song);

      // Play the sound, and watch for the case where onplay never fires.
      this.sound.play();
      this._armPlayWatchdog();
      return true;
    } catch (error) {
      console.error('Failed to load and play song:', error);
      return false;
    }
  }

  // Play current song
  play() {
    if (this.sound && (this.isPaused || this.isStopped)) {
      this._wantPlaying = true;
      this._playRetries = 0;
      this.sound.play();
      this._armPlayWatchdog();
    }
  }

  // Pause current song
  pause() {
    if (this.sound && this.isPlaying) {
      this._wantPlaying = false;
      this._clearPlayWatchdog();
      this.sound.pause();
    }
  }

  // Stop current song
  stop() {
    this._wantPlaying = false;
    this._clearPlayWatchdog();
    if (this.sound) {
      this.sound.stop();
    }
  }

  // --- Stall recovery -------------------------------------------------------

  // After we ask the audio to play, confirm it actually started. If onplay
  // hasn't fired shortly, the browser deferred/blocked it (lock screen,
  // autoplay policy, transient stall) — retry a bounded number of times. As
  // soon as the OS allows audio one of these retries catches.
  _armPlayWatchdog() {
    this._clearPlayWatchdog();
    this._playWatchdog = setTimeout(() => {
      this._playWatchdog = null;
      if (!this._wantPlaying || this.isPlaying || !this.sound) return;
      if (this._playRetries >= 8) {
        // Give up auto-retrying; unlock + visibility handlers remain as a net.
        console.warn('Audio: still stalled after retries; awaiting unlock/visibility');
        this._emitDiag('play_giveup');
        return;
      }
      this._playRetries += 1;
      console.warn(`Audio: playback stalled at start, retry ${this._playRetries}`);
      try { this.sound.play(); } catch (e) {}
      this._armPlayWatchdog();
    }, 2500);
  }

  _clearPlayWatchdog() {
    if (this._playWatchdog) {
      clearTimeout(this._playWatchdog);
      this._playWatchdog = null;
    }
  }

  // Called when the page regains focus/visibility. If we should be playing but
  // the audio never actually started (the "advanced but silent" stall), kick
  // it — this automates the manual stop/start the host would otherwise need.
  nudgeIfStalled() {
    if (this._wantPlaying && this.sound && !this.isPlaying) {
      console.warn('Audio: nudging stalled playback after visibility/focus regain');
      this._emitDiag('nudge');
      this._playRetries = 0;
      try { this.sound.play(); } catch (e) {}
      this._armPlayWatchdog();
    }
  }

  // Progress watchdog. Howler can report "playing" (onplay fired) while the
  // underlying <audio> element is wedged and currentTime never advances — the
  // iOS auto-advance/lock freeze where is_playing stays true but position is
  // pinned (at 0 after a song change, or mid-track). The play() watchdog above
  // only covers the "never started" case (isPlaying false), so this handles the
  // "playing but frozen" case. Called ~once/second from the controller's time
  // loop — JS keeps ticking while the page is foregrounded, which is exactly
  // when these freezes occur (the server still sees heartbeats during them).
  checkProgress() {
    if (!this._wantPlaying || !this.isPlaying || !this.sound) {
      this._lastProgressPos = null;
      this._progressStallTicks = 0;
      return;
    }
    const pos = this.getCurrentTime();
    const dur = this.getDuration();
    // Near the natural end — let onend drive the advance; don't false-trip.
    if (dur && isFinite(dur) && pos >= dur - 0.6) {
      this._lastProgressPos = pos;
      this._progressStallTicks = 0;
      return;
    }
    if (this._lastProgressPos !== null && Math.abs(pos - this._lastProgressPos) < 0.05) {
      this._progressStallTicks += 1;
      if (this._progressStallTicks >= 4) { // ~4s "playing" with zero movement
        this._progressStallTicks = 0;
        if (this._progressRecoveries < 3 && this.currentSong) {
          this._progressRecoveries += 1;
          console.warn(`Audio: playing but frozen at ${pos.toFixed(2)}s — reloading track (attempt ${this._progressRecoveries})`);
          this._emitDiag('stall_reload');
          this.loadAndPlay(this.currentSong);
        } else {
          // Reloads didn't unstick it — keep the party moving by skipping ahead.
          console.warn('Audio: still frozen after reloads — skipping to next track');
          this._emitDiag('stall_skip');
          this._progressRecoveries = 0;
          if (this.onEnd) this.onEnd();
        }
      }
    } else {
      // Advancing normally — clear the stall + recovery counters.
      this._progressStallTicks = 0;
      this._progressRecoveries = 0;
    }
    this._lastProgressPos = pos;
  }

  // Skip to beginning of current song
  restart() {
    if (this.sound) {
      this.sound.seek(0);
      if (this.isStopped) {
        this.play();
      }
    }
  }

  // Skip to next song
  skip() {
    this.stop();
    if (this.onSkip) {
      this.onSkip();
    }
  }

  // Get current playback info
  getPlaybackInfo() {
    return {
      currentSong: this.currentSong,
      currentTime: this.sound ? this.sound.seek() : 0,
      duration: this.sound ? this.sound.duration() : 0,
      isPlaying: this.isPlaying,
      isPaused: this.isPaused,
      isStopped: this.isStopped
    };
  }

  // Set volume (0.0 to 1.0)
  setVolume(volume) {
    // Clamp volume to valid range
    this.currentVolume = Math.max(0, Math.min(1, volume));
    
    // Apply to current sound if it exists
    if (this.sound) {
      this.sound.volume(this.currentVolume);
    }
  }

  // Get current volume
  getVolume() {
    return this.currentVolume;
  }

  // Get current time
  getCurrentTime() {
    return this.sound ? this.sound.seek() : 0;
  }

  // Get duration
  getDuration() {
    return this.sound ? this.sound.duration() : 0;
  }

  // --- Diagnostics ----------------------------------------------------------

  // A low-level snapshot of what the player is actually doing, shipped with the
  // heartbeat so it lands in the server log. The point is to watch track-edge
  // behaviour on a *locked* phone (where there's no console): is the next track
  // buffered ahead of the playhead (bufAhead), did the <audio> element stall
  // (ready/net), are the recovery watchdogs firing (retries/recoveries)?
  // Always safe to call; never throws.
  getDiagnostics() {
    const r = (n) => (typeof n === 'number' && isFinite(n)) ? Math.round(n * 100) / 100 : null;
    const pos = this.getCurrentTime();
    const dur = this.getDuration();
    const d = {
      want: this._wantPlaying,
      playing: this.isPlaying,
      paused: this.isPaused,
      stopped: this.isStopped,
      retries: this._playRetries,
      stallTicks: this._progressStallTicks,
      recoveries: this._progressRecoveries,
      pos: r(pos),
      dur: r(dur),
      remaining: (typeof dur === 'number' && isFinite(dur) && dur > 0) ? r(dur - pos) : null
    };
    try {
      if (this.sound) {
        d.howl = this.sound.state(); // 'unloaded' | 'loading' | 'loaded'
        // Reach the underlying HTML5 <audio> element (html5: true mode) for the
        // facts Howler doesn't surface: buffering and network/ready state.
        const inner = this.sound._sounds && this.sound._sounds[0];
        const node = inner && inner._node;
        if (node) {
          d.ready = node.readyState;     // 0 NOTHING .. 4 ENOUGH_DATA
          d.net = node.networkState;     // 0 EMPTY, 1 IDLE, 2 LOADING, 3 NO_SOURCE
          d.nodePaused = node.paused;
          if (node.buffered && node.buffered.length) {
            const end = node.buffered.end(node.buffered.length - 1);
            d.bufEnd = r(end);
            d.bufAhead = r(end - pos); // seconds buffered past the playhead
          } else {
            d.bufAhead = 0;
          }
        }
      }
    } catch (e) {
      d.err = String((e && e.message) || e);
    }
    if (typeof document !== 'undefined') d.vis = document.visibilityState;
    return d;
  }

  // Fire an out-of-band diagnostic heartbeat tagged with what just happened
  // (a stall, a blocked play, a skip), so the edge is captured between the
  // regular 10s heartbeats. No-op if the controller hasn't wired onDiag.
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

  // Clean up
  destroy() {
    this._wantPlaying = false;
    this._clearPlayWatchdog();
    if (this.sound) {
      this.sound.unload();
      this.sound = null;
    }
  }
}