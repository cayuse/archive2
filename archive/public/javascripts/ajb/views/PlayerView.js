// AJB PlayerView - the host's player page (React without JSX, no build step).
// Shares its look with the guest page through /stylesheets/ajb.css.
const PlayerView = {
  // Main Player App Component
  PlayerApp: function() {
    const el = React.createElement;
    const [state, setState] = React.useState({
      currentSong: null,
      isPlaying: false,
      isPaused: false,
      isStopped: true,
      currentTime: 0,
      duration: 0,
      volume: 0.8,
      isLoading: false,
      error: null,
      queue: [],
      history: [],
      historyHasMore: false,
      pauseArmed: false,
      awaitingResume: false,
      standing: null
    });
    const [controller, setController] = React.useState(null);

    // Initialize controller on mount
    React.useEffect(() => {
      const config = window.AJB_CONFIG;
      if (!config || !config.jukeboxId) {
        setState(prev => ({ ...prev, error: 'Missing configuration' }));
        return;
      }
      if (!config.apiToken) {
        setState(prev => ({ ...prev, error: 'No API token available - cannot authenticate with server' }));
        return;
      }

      let playerController;
      try {
        playerController = new PlayerController(config.jukeboxId, config.apiToken, config.sessionId);
      } catch (error) {
        console.error('Error creating PlayerController:', error);
        setState(prev => ({ ...prev, error: `Failed to initialize player: ${error.message}` }));
        return;
      }

      const merge = (patch) => setState(prev => ({ ...prev, ...patch }));
      playerController.onLoading = (isLoading) => merge({ isLoading });
      playerController.onError = (error) => merge({ error });
      playerController.onSongChange = (currentSong) => merge({ currentSong });
      playerController.onTimeUpdate = (currentTime, duration) => merge({ currentTime, duration });
      playerController.onQueueChange = (queue) => merge({ queue });
      playerController.onHistoryChange = (history, historyHasMore) => merge({ history, historyHasMore });
      playerController.onStandingChange = (standing) => merge({ standing });
      playerController.onPauseModeChange = (pauseArmed, awaitingResume) => merge({ pauseArmed, awaitingResume });

      setController(playerController);
      return () => playerController.destroy();
    }, []);

    // The controller has no change event for transport state, so poll it.
    React.useEffect(() => {
      if (!controller) return;
      const updateState = () => {
        const { isPlaying, isPaused, isStopped, volume } = controller.getState();
        setState(prev => ({ ...prev, isPlaying, isPaused, isStopped, volume }));
      };
      updateState();
      const interval = setInterval(updateState, 1000);
      return () => clearInterval(interval);
    }, [controller]);

    const config = window.AJB_CONFIG || {};
    const dismissError = () => setState(prev => ({ ...prev, error: null }));

    if (!controller) {
      return el('div', { className: 'ajb-player' },
        el(PlayerView.Header, { name: config.jukeboxName, status: 'Starting' }),
        state.error
          ? el(PlayerView.ErrorMessage, { error: state.error, onDismiss: dismissError })
          : el('div', { className: 'ajb-loading' },
              el('div', { className: 'spinner-border', role: 'status' }),
              el('p', null, 'Starting player…'))
      );
    }

    const status = state.isLoading ? 'Loading'
      : state.isPlaying ? 'Playing'
      : state.awaitingResume ? 'Holding'
      : state.isPaused ? 'Paused'
      : 'Stopped';

    return el('div', { className: 'ajb-player' },
      el(PlayerView.Header, { name: config.jukeboxName, status, isPlaying: state.isPlaying }),
      state.error && el(PlayerView.ErrorMessage, { error: state.error, onDismiss: dismissError }),
      el('div', { className: 'ajb-player-grid' },
        el('div', { className: 'ajb-player-side' },
          el(PlayerView.NowPlaying, {
            song: state.currentSong,
            status,
            isPlaying: state.isPlaying,
            currentTime: state.currentTime,
            duration: state.duration
          },
            el(PlayerView.Controls, {
              isPlaying: state.isPlaying,
              isLoading: state.isLoading,
              pauseArmed: state.pauseArmed,
              awaitingResume: state.awaitingResume,
              onPlay: () => controller.play(),
              onPause: () => controller.pause(),
              onStop: () => controller.stop(),
              onSkip: () => controller.skip(),
              onRestart: () => controller.restart(),
              onTogglePauseAfter: () => controller.togglePauseAfterSong()
            }),
            el(PlayerView.VolumeControl, {
              volume: state.volume,
              onChange: (volume) => controller.setVolume(volume)
            }),
            el(PlayerView.FeedbackBar, {
              song: state.currentSong,
              standing: state.standing,
              onFeedback: (kind) => controller.feedback(kind)
            })
          ),
          el(PlayerView.JoinPanel)
        ),
        el('div', { className: 'ajb-player-main' },
          el(PlayerView.QueuePanel, {
            queue: state.queue,
            onRemove: (songId) => controller.removeFromQueue(songId),
            onPromote: (songId) => controller.promoteInQueue(songId),
            onPlayNext: (songId) => controller.playNextInQueue(songId)
          }),
          el(PlayerView.HistoryPanel, {
            history: state.history,
            hasMore: state.historyHasMore,
            onLoadMore: () => controller.loadMoreHistory(),
            onReRequest: (songId) => controller.requestFromHistory(songId)
          })
        )
      )
    );
  },

  // Jukebox name and the player's live state.
  Header: function({ name, status, isPlaying }) {
    const el = React.createElement;
    return el('header', { className: 'ajb-header ajb-player-header' },
      el('div', { className: 'ajb-header-top' },
        el('span', { className: 'ajb-header-name' }, name || 'AJB Player'),
        el('span', { className: 'ajb-tag ajb-role' }, 'Host'),
        el('span', { className: `ajb-pill ${isPlaying ? 'is-playing' : ''}` },
          el('span', { className: 'ajb-pill-dot' }), status)
      )
    );
  },

  // Current song, progress, and (as children) the controls that act on it.
  NowPlaying: function({ song, status, isPlaying, currentTime, duration, children }) {
    const el = React.createElement;
    const length = duration || (song && song.duration) || 0;
    const percent = length > 0 ? Math.min((currentTime / length) * 100, 100) : 0;

    return el('section', { className: 'ajb-card ajb-player-now' },
      el('div', { className: 'ajb-current' },
        el('div', { className: `ajb-current-art ${isPlaying ? 'is-playing' : ''}` },
          el('i', { className: `fas ${isPlaying ? 'fa-volume-high' : 'fa-music'}` })),
        el('div', { className: 'ajb-current-body' },
          el('div', { className: 'ajb-eyebrow' }, song ? status : 'Ready'),
          el('h2', { className: 'ajb-current-title' }, song ? song.title : 'Nothing playing'),
          el('p', { className: 'ajb-current-artist' },
            song ? (song.artist || 'Unknown artist') : 'Press play to start the jukebox'),
          song && song.album && el('p', { className: 'ajb-muted ajb-small' }, song.album)
        )
      ),
      el('div', { className: 'ajb-progress' },
        el('div', {
          className: 'ajb-progress-track',
          role: 'progressbar',
          'aria-valuemin': 0,
          'aria-valuemax': 100,
          'aria-valuenow': Math.round(percent)
        },
          el('div', {
            className: `ajb-progress-fill ${isPlaying ? 'is-playing' : ''}`,
            style: { width: `${percent}%` }
          })
        ),
        el('div', { className: 'ajb-progress-times' },
          el('span', null, PlayerView.formatTime(currentTime)),
          el('span', null, `-${PlayerView.formatTime(Math.max(length - currentTime, 0))}`)
        )
      ),
      children
    );
  },

  // Transport: restart, play/pause, stop, skip, plus "pause after song".
  Controls: function({ isPlaying, isLoading, pauseArmed, awaitingResume, onPlay, onPause, onStop, onSkip, onRestart, onTogglePauseAfter }) {
    const el = React.createElement;
    const iconButton = (icon, label, onClick, extraClass = 'ajb-btn-ghost') =>
      el('button', {
        type: 'button',
        className: `ajb-btn ${extraClass}`,
        onClick,
        disabled: isLoading,
        title: label,
        'aria-label': label
      }, el('i', { className: `fas ${icon}` }));

    return el('div', { className: 'ajb-controls' },
      awaitingResume && el('p', { className: 'ajb-hold' },
        el('i', { className: 'fas fa-pause' }), ' Paused between songs. Press play to continue.'),
      el('div', { className: 'ajb-transport-row' },
        iconButton('fa-backward-step', 'Restart song', onRestart),
        isPlaying
          ? iconButton('fa-pause', 'Pause', onPause, 'ajb-btn-primary ajb-btn-main')
          : iconButton('fa-play', 'Play', onPlay, 'ajb-btn-primary ajb-btn-main'),
        iconButton('fa-stop', 'Stop', onStop),
        iconButton('fa-forward-step', 'Skip song', onSkip)
      ),
      el('button', {
        type: 'button',
        className: `ajb-btn ajb-btn-block ${pauseArmed ? 'ajb-btn-armed' : 'ajb-btn-ghost'}`,
        'aria-pressed': pauseArmed,
        onClick: onTogglePauseAfter,
        title: 'Pause after the current song finishes (for announcements)'
      },
        el('i', { className: 'fas fa-hourglass-half' }),
        pauseArmed ? ' Will pause after this song' : ' Pause after this song'
      )
    );
  },

  // Volume Control
  VolumeControl: function({ volume, onChange }) {
    const el = React.createElement;
    return el('label', { className: 'ajb-volume' },
      el('i', { className: 'fas fa-volume-low', 'aria-hidden': true }),
      el('input', {
        type: 'range',
        className: 'ajb-range',
        'aria-label': 'Volume',
        min: 0,
        max: 1,
        step: 0.05,
        value: volume,
        onChange: (e) => onChange(parseFloat(e.target.value))
      }),
      el('span', { className: 'ajb-volume-value' }, `${Math.round(volume * 100)}%`)
    );
  },

  // Thumbs, "sick of it" and "never" for the song now playing, plus a link to the station's tuning
  // page. Feedback belongs to this jukebox; on a station it also shapes what plays next.
  FeedbackBar: function({ song, standing, onFeedback }) {
    const el = React.createElement;
    const cfg = window.AJB_CONFIG || {};
    if (!cfg.radio) return null;
    const button = (kind, icon, label, title) => {
      const active = standing === kind;
      return el('button', {
        key: kind,
        type: 'button',
        className: `ajb-btn ${active ? 'ajb-btn-armed' : 'ajb-btn-ghost'}`,
        'aria-pressed': active,
        'aria-label': label || title,
        disabled: !song,
        title,
        onClick: () => onFeedback(active ? 'clear' : kind)
      }, el('i', { className: `fas ${icon}` }), label ? ` ${label}` : null);
    };
    return el('div', { className: 'ajb-feedback' },
      button('up', 'fa-thumbs-up', 'More like this', 'Thumbs up: more like this on this station'),
      button('down', 'fa-thumbs-down', 'Not here', 'Thumbs down: not on this station (skips it)'),
      button('tired', 'fa-bed', 'Sick of it', 'Shelve this song for a month on all your stations (skips it)'),
      button('never', 'fa-ban', '', 'Never play this for me (skips it)'),
      cfg.tuneUrl && el('a', { className: 'ajb-link', href: cfg.tuneUrl, target: '_blank', rel: 'noopener' },
        'Tune this station')
    );
  },

  // Error Message
  ErrorMessage: function({ error, onDismiss }) {
    const el = React.createElement;
    return el('div', { className: 'ajb-alert', role: 'alert' },
      el('span', null, error),
      el('button', { type: 'button', className: 'ajb-alert-close', onClick: onDismiss, 'aria-label': 'Dismiss' },
        el('i', { className: 'fas fa-xmark' }))
    );
  },

  // Upcoming queue, numbered in play order, with play-next / bump / remove.
  QueuePanel: function({ queue, onRemove, onPromote, onPlayNext }) {
    const el = React.createElement;
    const items = queue || [];
    const action = (icon, label, onClick, extraClass = '') =>
      el('button', {
        type: 'button',
        className: `ajb-btn ajb-btn-ghost ${extraClass}`,
        title: label,
        'aria-label': label,
        onClick
      }, el('i', { className: `fas ${icon}` }));

    return el('section', { className: 'ajb-card' },
      el('div', { className: 'ajb-card-head' },
        el('h2', { className: 'ajb-card-title' }, 'Up next'),
        el('span', { className: 'ajb-count' }, items.length)
      ),
      items.length === 0
        ? el('p', { className: 'ajb-empty' },
            'The queue is empty. Songs will fill in from the assigned playlists when you press play.')
        : el('ol', { className: 'ajb-list' },
            items.map((item, index) => {
              const requested = item.source === 'requested';
              return el('li', { key: item.id, className: `ajb-row ${requested ? 'is-requested' : ''}` },
                el('span', { className: 'ajb-row-index' }, index + 1),
                el('div', { className: 'ajb-row-text' },
                  el('div', { className: 'ajb-row-title' }, item.song.title),
                  el('div', { className: 'ajb-row-sub' }, item.song.artist || 'Unknown artist')
                ),
                requested && el('span', { className: 'ajb-tag ajb-hide-narrow' }, 'Requested'),
                el('div', { className: 'ajb-row-actions' },
                  index > 0 && action('fa-angles-up', `Play ${item.song.title} next`, () => onPlayNext(item.song.id)),
                  !requested && action('fa-arrow-up', `Bump ${item.song.title} ahead of auto-picked songs`,
                    () => onPromote(item.song.id)),
                  action('fa-trash', `Remove ${item.song.title}`, () => onRemove(item.song.id), 'ajb-btn-danger')
                )
              );
            })
          )
    );
  },

  // Play history (most recent first), loading more as the end scrolls into view.
  HistoryPanel: function({ history, hasMore, onLoadMore, onReRequest }) {
    const el = React.createElement;
    const items = history || [];
    const sentinel = React.useRef(null);

    React.useEffect(() => {
      if (!hasMore || !sentinel.current) return;
      const observer = new IntersectionObserver((entries) => {
        if (entries[0].isIntersecting) onLoadMore();
      });
      observer.observe(sentinel.current);
      return () => observer.disconnect();
    }, [hasMore, items.length]);

    return el('section', { className: 'ajb-card' },
      el('div', { className: 'ajb-card-head' },
        el('h2', { className: 'ajb-card-title' }, 'Played')
      ),
      items.length === 0
        ? el('p', { className: 'ajb-empty' }, 'Nothing has played yet.')
        : el('ul', { className: 'ajb-list' },
            items.map((item) =>
              el('li', { key: item.id, className: 'ajb-row' },
                el('div', { className: 'ajb-row-text' },
                  el('div', { className: 'ajb-row-title' }, item.song.title),
                  el('div', { className: 'ajb-row-sub' }, item.song.artist || 'Unknown artist')
                ),
                item.source === 'requested' && el('span', { className: 'ajb-tag ajb-hide-narrow' }, 'Requested'),
                el('button', {
                  type: 'button',
                  className: 'ajb-btn ajb-btn-ghost',
                  title: 'Play again',
                  'aria-label': `Queue ${item.song.title} again`,
                  onClick: () => onReRequest(item.song.id)
                }, el('i', { className: 'fas fa-rotate-right' }))
              )
            )
          ),
      hasMore && el('div', { ref: sentinel, className: 'ajb-empty ajb-small' }, 'Loading more…')
    );
  },

  // QR code + URL + code so guests can join from their phones.
  JoinPanel: function() {
    const el = React.createElement;
    const cfg = window.AJB_CONFIG || {};
    // Short, shareable URL (/j/<slug>); falls back to the canonical path if the
    // slug isn't present for some reason.
    const guestUrl = cfg.sessionId
      ? window.location.origin + '/j/' + cfg.sessionId
      : window.location.origin + '/jukeboxes/' + cfg.jukeboxId + '/guest';
    const qrRef = React.useRef(null);

    React.useEffect(() => {
      if (qrRef.current && typeof QRCode !== 'undefined') {
        qrRef.current.innerHTML = '';
        new QRCode(qrRef.current, {
          text: guestUrl,
          width: 160,
          height: 160,
          correctLevel: QRCode.CorrectLevel.M
        });
      }
    }, [guestUrl]);

    return el('section', { className: 'ajb-card ajb-join' },
      el('div', { ref: qrRef, className: 'ajb-join-qr' }),
      el('div', { className: 'ajb-join-text' },
        el('h2', { className: 'ajb-card-title' }, 'Scan to request songs'),
        el('a', { href: guestUrl, target: '_blank', rel: 'noopener', className: 'ajb-link ajb-join-url' },
          guestUrl.replace(/^https?:\/\//, '')),
        cfg.hasPassword && el('p', { className: 'ajb-join-code' },
          el('span', { className: 'ajb-muted' }, 'Code '),
          el('strong', null, cfg.guestPassword))
      )
    );
  },

  // Utility function to format time
  formatTime: function(seconds) {
    if (!seconds || isNaN(seconds)) return '0:00';
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return mins + ':' + secs.toString().padStart(2, '0');
  }
};
