// Guest View - React components for the guest interface (no JSX, no build step)
const h = React.createElement;

const GuestView = {
  // State keys the UI renders from; anything else in GuestState is ignored here.
  UI_KEYS: [
    'authenticated', 'role', 'offline', 'loading', 'error', 'notice', 'currentView',
    'currentSong', 'currentPosition', 'isPlaying', 'queue', 'totalQueueCount',
    'history', 'historyHasMore', 'jukeboxName',
    'searchResults', 'searchQuery', 'searchLoading', 'searchPagination'
  ],

  // Main Guest App Component
  GuestApp: function() {
    const [state, setState] = React.useState({ authenticated: false, currentView: 'now-playing' });
    const [controller, setController] = React.useState(null);

    React.useEffect(() => {
      const config = window.AJB_GUEST_CONFIG;
      if (!config || !config.jukeboxId) return;

      const guestController = new GuestController(config.jukeboxId, config.password, config.sessionId);
      setController(guestController);

      const unsubscribe = guestController.state.subscribe((newState) => {
        setState((prev) => {
          const next = {};
          GuestView.UI_KEYS.forEach((key) => { next[key] = newState[key]; });
          // Skip the re-render when nothing the UI shows has changed.
          const changed = GuestView.UI_KEYS.some(
            (key) => JSON.stringify(prev[key]) !== JSON.stringify(next[key])
          );
          return changed ? next : prev;
        });
      });

      return () => {
        unsubscribe();
        guestController.destroy();
      };
    }, []);

    const config = window.AJB_GUEST_CONFIG || {};
    const jukeboxName = state.jukeboxName || config.jukeboxName || 'Jukebox';

    if (!controller) {
      return h('div', { className: 'guest-loading' },
        h('div', { className: 'spinner-border', role: 'status' }),
        h('p', null, 'Loading…')
      );
    }

    if (state.offline) {
      return h(GuestView.ClosedView);
    }

    if (!state.authenticated) {
      return h(GuestView.AuthView, {
        jukeboxName,
        onAuthenticate: (password) => controller.authenticate(password),
        loading: state.loading,
        error: state.error
      });
    }

    const views = {
      'now-playing': GuestView.NowPlayingView,
      'request-songs': GuestView.RequestSongsView,
      'play-history': GuestView.HistoryView
    };

    return h('div', { className: 'guest-app' },
      h(GuestView.Header, {
        jukeboxName,
        isAdmin: state.role === 'admin',
        isPlaying: !!state.isPlaying,
        hasSong: !!state.currentSong,
        currentView: state.currentView,
        onSwitch: {
          'now-playing': () => controller.switchToNowPlaying(),
          'request-songs': () => controller.switchToRequestSongs(),
          'play-history': () => controller.switchToHistory()
        }
      }),
      state.error && h(GuestView.ErrorMessage, {
        error: state.error,
        onDismiss: () => controller.state.clearError()
      }),
      h('main', { className: 'guest-main' },
        h(views[state.currentView] || GuestView.NowPlayingView, { controller, state })
      ),
      state.notice && h('div', { className: 'guest-toast', role: 'status' }, state.notice)
    );
  },

  // Shown when the jukebox has no live player (host closed it).
  ClosedView: function() {
    const cfg = window.AJB_GUEST_CONFIG || {};
    const name = cfg.jukeboxName || 'This jukebox';
    return h('div', { className: 'guest-closed' },
      h('div', { className: 'guest-closed-emoji' }, '🎉'),
      h('h1', null, `${name} is closed`),
      h('p', { className: 'guest-muted' }, 'Thanks for coming! 👋'),
      h('p', { className: 'guest-muted guest-small' },
        'The host stopped the music. If they start it back up, just reload this page to rejoin.'
      )
    );
  },

  // Authentication View
  AuthView: function({ jukeboxName, onAuthenticate, loading, error }) {
    const [password, setPassword] = React.useState('');

    const handleSubmit = (e) => {
      e.preventDefault();
      onAuthenticate(password);
    };

    return h('div', { className: 'guest-auth' },
      h('div', { className: 'guest-card guest-auth-card' },
        h('div', { className: 'guest-auth-icon' }, '🎵'),
        h('h1', { className: 'guest-auth-title' }, jukeboxName),
        h('p', { className: 'guest-muted' }, 'Enter the jukebox code to see what’s playing and request songs.'),
        h('form', { onSubmit: handleSubmit, autoComplete: 'off' },
          h('input', {
            // type=text (not password): this is a shared party code people
            // read off a screen/QR, so masking buys nothing and it stops
            // password managers (1Password etc.) from hijacking the field.
            type: 'text',
            className: 'guest-input',
            placeholder: 'Jukebox code',
            'aria-label': 'Jukebox code',
            value: password,
            onChange: (e) => setPassword(e.target.value),
            required: true,
            disabled: loading,
            autoCapitalize: 'none',
            autoCorrect: 'off',
            name: 'jukebox-access-code',
            autoComplete: 'off',
            'data-1p-ignore': 'true',
            'data-lpignore': 'true',
            'data-bwignore': 'true',
            'data-dashlane-ignore': 'true',
            'data-form-type': 'other'
          }),
          h('button', { type: 'submit', className: 'guest-btn guest-btn-primary guest-btn-block', disabled: loading },
            loading ? 'Connecting…' : 'Join')
        ),
        error && h('div', { className: 'guest-alert', role: 'alert' }, error)
      )
    );
  },

  // One compact bar: jukebox name + live state, then the three tabs.
  Header: function({ jukeboxName, isAdmin, isPlaying, hasSong, currentView, onSwitch }) {
    const tabs = [
      ['now-playing', 'fa-music', 'Now Playing'],
      ['request-songs', 'fa-magnifying-glass', 'Request'],
      ['play-history', 'fa-clock-rotate-left', 'History']
    ];
    const stateLabel = isPlaying ? 'Playing' : (hasSong ? 'Paused' : 'Idle');

    return h('header', { className: 'guest-header' },
      h('div', { className: 'guest-header-top' },
        h('span', { className: 'guest-header-name' }, jukeboxName),
        isAdmin && h('span', { className: 'guest-tag guest-role' }, 'Admin'),
        h('span', { className: `guest-pill ${isPlaying ? 'is-playing' : ''}` },
          h('span', { className: 'guest-pill-dot' }), stateLabel)
      ),
      h('nav', { className: 'guest-tabs', role: 'tablist' },
        tabs.map(([view, icon, label]) =>
          h('button', {
            key: view,
            type: 'button',
            role: 'tab',
            'aria-selected': currentView === view,
            className: `guest-tab ${currentView === view ? 'is-active' : ''}`,
            onClick: onSwitch[view]
          }, h('i', { className: `fas ${icon}` }), h('span', null, label))
        )
      )
    );
  },

  // Now Playing View
  NowPlayingView: function({ controller, state }) {
    React.useEffect(() => {
      controller.updatePlaybackInfo();
      controller.updateQueue();
    }, [controller]);

    const isAdmin = state.role === 'admin';

    return h('div', { className: 'guest-now' },
      h('div', { className: 'guest-now-side' },
        h(GuestView.CurrentSongDisplay, {
          song: state.currentSong,
          position: parseFloat(state.currentPosition) || 0,
          isPlaying: !!state.isPlaying
        }),
        isAdmin && h(GuestView.Transport, {
          isPlaying: !!state.isPlaying,
          onCommand: (command) => controller.sendPlayerCommand(command)
        })
      ),
      h(GuestView.QueueDisplay, {
        queue: state.queue || [],
        totalCount: state.totalQueueCount || 0,
        isAdmin,
        onPromote: (song) => controller.promoteSong(song.id, song.title),
        onRemove: (song) => controller.removeSong(song.id, song.title)
      })
    );
  },

  // Admin code only: remote control for the host's player.
  Transport: function({ isPlaying, onCommand }) {
    return h('section', { className: 'guest-card guest-transport', 'aria-label': 'Player controls' },
      h('button', {
        type: 'button',
        className: 'guest-btn guest-btn-primary',
        onClick: () => onCommand(isPlaying ? 'pause' : 'play')
      }, h('i', { className: `fas ${isPlaying ? 'fa-pause' : 'fa-play'}` }), isPlaying ? ' Pause' : ' Play'),
      h('button', { type: 'button', className: 'guest-btn guest-btn-ghost', onClick: () => onCommand('skip') },
        h('i', { className: 'fas fa-forward-step' }), ' Skip')
    );
  },

  // Current song card with a progress bar
  CurrentSongDisplay: function({ song, position, isPlaying }) {
    if (!song) {
      return h('section', { className: 'guest-card guest-current is-empty' },
        h('div', { className: 'guest-current-art' }, h('i', { className: 'fas fa-music' })),
        h('div', { className: 'guest-current-body' },
          h('h2', { className: 'guest-current-title' }, 'Nothing playing'),
          h('p', { className: 'guest-muted' }, 'Waiting for the host to start the music…')
        )
      );
    }

    return h('section', { className: 'guest-card guest-current' },
      h('div', { className: `guest-current-art ${isPlaying ? 'is-playing' : ''}` },
        h('i', { className: `fas ${isPlaying ? 'fa-volume-high' : 'fa-pause'}` })),
      h('div', { className: 'guest-current-body' },
        h('div', { className: 'guest-eyebrow' }, isPlaying ? 'Now playing' : 'Paused'),
        h('h2', { className: 'guest-current-title' }, song.title || 'Unknown title'),
        h('p', { className: 'guest-current-artist' }, song.artist || 'Unknown artist'),
        song.album && h('p', { className: 'guest-muted guest-small' }, song.album),
        h(GuestView.ProgressBar, {
          // Remount per song so the ticker restarts from the new track's position.
          key: song.id,
          position,
          duration: song.duration || 0,
          isPlaying
        })
      )
    );
  },

  // The host reports its position every ~10s; between reports we advance the
  // bar locally so it moves smoothly instead of jumping.
  ProgressBar: function({ position, duration, isPlaying }) {
    const [shown, setShown] = React.useState(position);

    React.useEffect(() => {
      setShown(position);
      if (!isPlaying) return;
      const syncedAt = Date.now();
      const timer = setInterval(() => {
        setShown(position + (Date.now() - syncedAt) / 1000);
      }, 250);
      return () => clearInterval(timer);
    }, [position, isPlaying]);

    const current = duration > 0 ? Math.min(shown, duration) : shown;
    const percent = duration > 0 ? (current / duration) * 100 : 0;

    return h('div', { className: 'guest-progress' },
      h('div', {
        className: 'guest-progress-track',
        role: 'progressbar',
        'aria-valuemin': 0,
        'aria-valuemax': 100,
        'aria-valuenow': Math.round(percent)
      },
        h('div', {
          className: `guest-progress-fill ${isPlaying ? 'is-playing' : ''}`,
          style: { width: `${percent}%` }
        })
      ),
      h('div', { className: 'guest-progress-times' },
        h('span', null, GuestState.formatTime(current)),
        h('span', null, `-${GuestState.formatTime(Math.max(duration - current, 0))}`)
      )
    );
  },

  // Upcoming songs, numbered in the order they will play
  QueueDisplay: function({ queue, totalCount, isAdmin, onPromote, onRemove }) {
    return h('section', { className: 'guest-card guest-queue' },
      h('div', { className: 'guest-card-head' },
        h('h2', { className: 'guest-card-title' }, 'Up next'),
        h('span', { className: 'guest-count' }, totalCount || queue.length)
      ),
      queue.length === 0
        ? h('p', { className: 'guest-empty' }, 'The queue is empty. Request a song to get things going.')
        : h('ol', { className: 'guest-list' },
            queue.map((item, index) => {
              const requested = item.source === 'requested';
              return h('li', { key: item.song.id, className: `guest-row ${requested ? 'is-requested' : ''}` },
                h('span', { className: 'guest-row-index' }, index + 1),
                h('div', { className: 'guest-row-text' },
                  h('div', { className: 'guest-row-title' }, item.song.title),
                  h('div', { className: 'guest-row-sub' },
                    `${item.song.artist || 'Unknown artist'} · ${GuestState.formatTime(item.song.duration || 0)}`)
                ),
                requested && h('span', { className: 'guest-tag' }, 'Requested'),
                isAdmin && !requested && h('button', {
                  type: 'button',
                  className: 'guest-btn guest-btn-ghost',
                  title: 'Move this song ahead of the auto-picked ones',
                  'aria-label': `Bump ${item.song.title}`,
                  onClick: () => onPromote(item.song)
                }, h('i', { className: 'fas fa-arrow-up' })),
                isAdmin && h('button', {
                  type: 'button',
                  className: 'guest-btn guest-btn-ghost guest-btn-danger',
                  title: 'Remove from the queue',
                  'aria-label': `Remove ${item.song.title}`,
                  onClick: () => onRemove(item.song)
                }, h('i', { className: 'fas fa-trash' }))
              );
            })
          )
    );
  },

  // Request Songs View
  RequestSongsView: function({ controller, state }) {
    const [text, setText] = React.useState(state.searchQuery || '');
    const debounce = React.useRef(null);

    React.useEffect(() => () => clearTimeout(debounce.current), []);

    const runSearch = (value) => {
      setText(value);
      clearTimeout(debounce.current);
      const query = value.trim();
      if (!query) {
        controller.clearSearch();
        return;
      }
      debounce.current = setTimeout(() => controller.searchSongs(query), 400);
    };

    const results = state.searchResults || [];
    const pagination = state.searchPagination;
    const query = (state.searchQuery || '').trim();
    const searching = !!state.searchLoading;
    const queueSource = {};
    (state.queue || []).forEach((item) => { queueSource[item.song.id] = item.source; });

    let body;
    if (!text.trim()) {
      body = h('p', { className: 'guest-empty' },
        'Search by song, artist, album or genre. Requests play before the auto-picked songs.');
    } else if (results.length === 0 && (searching || text.trim() !== query)) {
      body = h('p', { className: 'guest-empty' },
        h('span', { className: 'spinner-border spinner-border-sm', role: 'status' }), ' Searching…');
    } else if (results.length === 0) {
      body = h('p', { className: 'guest-empty' }, `No songs found for “${query}”. Try fewer or different words.`);
    } else {
      body = h(React.Fragment, null,
        h('div', { className: 'guest-card-head' },
          h('h2', { className: 'guest-card-title' }, 'Results'),
          pagination && h('span', { className: 'guest-count' },
            pagination.total_count > results.length
              ? `${results.length} of ${pagination.total_count}`
              : `${results.length}`)
        ),
        h('ul', { className: 'guest-list' },
          results.map((song) => h(GuestView.SearchResultRow, {
            key: song.id,
            song,
            queuedAs: queueSource[song.id],
            isAdmin: state.role === 'admin',
            onRequest: () => controller.requestSong(song.id, song.title)
          }))
        ),
        pagination && pagination.has_more && h('button', {
          type: 'button',
          className: 'guest-btn guest-btn-ghost guest-btn-block guest-more',
          disabled: searching,
          onClick: () => controller.loadMoreSearchResults()
        }, searching ? 'Loading…' : 'Load more')
      );
    }

    return h('div', { className: 'guest-request' },
      h('div', { className: 'guest-search' },
        h('i', { className: 'fas fa-magnifying-glass guest-search-icon' }),
        h('input', {
          type: 'search',
          className: 'guest-input guest-search-input',
          placeholder: 'Search songs, artists, albums…',
          'aria-label': 'Search songs',
          value: text,
          autoComplete: 'off',
          autoCorrect: 'off',
          enterKeyHint: 'search',
          onChange: (e) => runSearch(e.target.value)
        }),
        text && h('button', {
          type: 'button',
          className: 'guest-search-clear',
          'aria-label': 'Clear search',
          onClick: () => runSearch('')
        }, h('i', { className: 'fas fa-xmark' }))
      ),
      h('section', { className: 'guest-card' }, body)
    );
  },

  // One search result. The button reflects where the song already stands in
  // the queue, so a request never ends in an "already queued" error.
  SearchResultRow: function({ song, queuedAs, isAdmin, onRequest }) {
    const [busy, setBusy] = React.useState(false);
    const request = async () => {
      setBusy(true);
      await onRequest();
      setBusy(false);
    };
    const details = [song.artist || 'Unknown artist', song.album, GuestState.formatTime(song.duration || 0)]
      .filter(Boolean).join(' · ');

    let action;
    if (queuedAs === 'requested') {
      action = h('span', { className: 'guest-tag is-done' }, h('i', { className: 'fas fa-check' }), ' Requested');
    } else if (queuedAs && !isAdmin) {
      // Only an admin code can reorder the queue, so a guest just sees it's coming.
      action = h('span', { className: 'guest-tag is-quiet' }, 'In queue');
    } else if (queuedAs) {
      action = h('button', { type: 'button', className: 'guest-btn guest-btn-ghost', disabled: busy, onClick: request },
        h('i', { className: 'fas fa-arrow-up' }), ' Bump');
    } else {
      action = h('button', { type: 'button', className: 'guest-btn guest-btn-primary', disabled: busy, onClick: request },
        busy ? 'Adding…' : 'Request');
    }

    return h('li', { className: 'guest-row' },
      h('div', { className: 'guest-row-text' },
        h('div', { className: 'guest-row-title' }, song.title),
        h('div', { className: 'guest-row-sub' }, details)
      ),
      action
    );
  },

  // Play History View: infinite-scrolling, with a "play it again" button per song.
  HistoryView: function({ controller, state }) {
    const history = state.history || [];
    const hasMore = !!state.historyHasMore;
    const sentinel = React.useRef(null);

    // Load the next page when the end of the list scrolls into view.
    React.useEffect(() => {
      if (!hasMore || !sentinel.current) return;
      const observer = new IntersectionObserver((entries) => {
        if (entries[0].isIntersecting) controller.loadMoreHistory();
      });
      observer.observe(sentinel.current);
      return () => observer.disconnect();
    }, [hasMore, history.length, controller]);

    return h('section', { className: 'guest-card' },
      h('div', { className: 'guest-card-head' },
        h('h2', { className: 'guest-card-title' }, 'Played')
      ),
      history.length === 0
        ? h('p', { className: 'guest-empty' }, 'Nothing has played yet.')
        : h('ul', { className: 'guest-list' },
            history.map((item) =>
              h('li', { key: item.id, className: 'guest-row' },
                h('div', { className: 'guest-row-text' },
                  h('div', { className: 'guest-row-title' }, item.song.title),
                  h('div', { className: 'guest-row-sub' }, item.song.artist || 'Unknown artist')
                ),
                item.source === 'requested' && h('span', { className: 'guest-tag' }, 'Requested'),
                h('button', {
                  type: 'button',
                  className: 'guest-btn guest-btn-ghost',
                  title: 'Request again',
                  'aria-label': `Request ${item.song.title} again`,
                  onClick: () => controller.requestSong(item.song.id, item.song.title)
                }, h('i', { className: 'fas fa-rotate-right' }))
              )
            )
          ),
      hasMore && h('div', { ref: sentinel, className: 'guest-empty guest-small' }, 'Loading more…')
    );
  },

  // Error Message
  ErrorMessage: function({ error, onDismiss }) {
    return h('div', { className: 'guest-alert', role: 'alert' },
      h('span', null, error),
      h('button', { type: 'button', className: 'guest-alert-close', onClick: onDismiss, 'aria-label': 'Dismiss' },
        h('i', { className: 'fas fa-xmark' }))
    );
  }
};
