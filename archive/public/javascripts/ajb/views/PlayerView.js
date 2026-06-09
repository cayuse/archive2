// AJB PlayerView - Simple React components without JSX
const PlayerView = {
  // Main Player App Component
  PlayerApp: function() {
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
      historyHasMore: false
    });

    const [controller, setController] = React.useState(null);

    // Initialize controller on mount
    React.useEffect(() => {
      console.log('🔍 PlayerView useEffect - Starting initialization...');
      console.log('🔍 window.AJB_CONFIG:', window.AJB_CONFIG);
      console.log('🔍 jukeboxId present:', !!window.AJB_CONFIG?.jukeboxId);
      console.log('🔍 apiToken present:', !!window.AJB_CONFIG?.apiToken);

      if (window.AJB_CONFIG && window.AJB_CONFIG.jukeboxId) {
        console.log('🔍 AJB_CONFIG exists and has jukeboxId, proceeding...');
        
        if (!window.AJB_CONFIG.apiToken) {
          console.warn('⚠️ No API token present! Player will not be able to authenticate with API');
          setState(prev => ({ ...prev, error: 'No API token available - cannot authenticate with server' }));
          return;
        }
        
        console.log('🔍 Creating PlayerController with:', {
          jukeboxId: window.AJB_CONFIG.jukeboxId,
          apiTokenLength: window.AJB_CONFIG.apiToken.length
        });
        
        try {
          const playerController = new PlayerController(window.AJB_CONFIG.jukeboxId, window.AJB_CONFIG.apiToken, window.AJB_CONFIG.sessionId);
          console.log('🔍 PlayerController created successfully:', playerController);
          
          // Set up event handlers
          playerController.onLoading = (isLoading) => {
            console.log('🔍 PlayerController onLoading:', isLoading);
            setState(prev => ({ ...prev, isLoading }));
          };

          playerController.onError = (error) => {
            console.log('🔍 PlayerController onError:', error);
            setState(prev => ({ ...prev, error }));
          };

          playerController.onSongChange = (song) => {
            console.log('🔍 PlayerController onSongChange:', song);
            setState(prev => ({ ...prev, currentSong: song }));
          };

          playerController.onTimeUpdate = (currentTime, duration) => {
            setState(prev => ({ ...prev, currentTime, duration }));
          };

          playerController.onQueueChange = (queue) => {
            setState(prev => ({ ...prev, queue }));
          };

          playerController.onHistoryChange = (history, historyHasMore) => {
            setState(prev => ({ ...prev, history, historyHasMore }));
          };

          console.log('🔍 Setting controller in state...');
          setController(playerController);
          console.log('🔍 Controller set successfully');

          // Clean up on unmount
          return () => {
            console.log('🔍 Cleaning up PlayerController...');
            if (playerController) {
              playerController.destroy();
            }
          };
        } catch (error) {
          console.error('❌ Error creating PlayerController:', error);
          setState(prev => ({ ...prev, error: `Failed to initialize player: ${error.message}` }));
        }
      } else {
        console.error('❌ Missing AJB_CONFIG or required fields');
        console.log('🔍 AJB_CONFIG exists:', !!window.AJB_CONFIG);
        console.log('🔍 jukeboxId exists:', !!window.AJB_CONFIG?.jukeboxId);
        setState(prev => ({ ...prev, error: 'Missing configuration' }));
      }
    }, []);

    // Update state when controller state changes
    React.useEffect(() => {
        if (controller) {
        const updateState = () => {
          const controllerState = controller.getState();
          setState(prev => ({
            ...prev,
            isPlaying: controllerState.isPlaying,
            isPaused: controllerState.isPaused,
            isStopped: controllerState.isStopped,
            volume: controllerState.volume
          }));
        };

        // Update immediately
        updateState();

        // Set up periodic updates
        const interval = setInterval(updateState, 1000);
        return () => clearInterval(interval);
      }
    }, [controller]);

    const handlePlay = () => controller && controller.play();
    const handlePause = () => controller && controller.pause();
    const handleStop = () => controller && controller.stop();
    const handleSkip = () => controller && controller.skip();
    const handleRestart = () => controller && controller.restart();
    const handleRemove = (songId) => controller && controller.removeFromQueue(songId);
    const handlePromote = (songId) => controller && controller.promoteInQueue(songId);
    const handlePlayNext = (songId) => controller && controller.playNextInQueue(songId);
    const handleLoadMoreHistory = () => controller && controller.loadMoreHistory();
    const handleReRequest = (songId) => controller && controller.requestFromHistory(songId);

    const handleVolumeChange = (e) => {
      const volume = parseFloat(e.target.value);
      if (controller) {
        controller.setVolume(volume);
      }
    };

    if (!controller) {
      return React.createElement('div', { className: 'text-center p-4' },
        React.createElement('div', { className: 'spinner-border text-primary', role: 'status' },
          React.createElement('span', { className: 'visually-hidden' }, 'Loading...')
        ),
        React.createElement('p', { className: 'mt-3' }, 'Initializing player...')
      );
    }

    return React.createElement('div', { className: 'player-app' },
      React.createElement('div', { className: 'row' },
        React.createElement('div', { className: 'col-md-8' },
          React.createElement(PlayerView.CurrentSongDisplay, { song: state.currentSong }),
          React.createElement(PlayerView.ProgressBar, { 
            currentTime: state.currentTime, 
            duration: state.duration 
          })
        ),
        React.createElement('div', { className: 'col-md-4' },
          React.createElement(PlayerView.Controls, { 
            isPlaying: state.isPlaying,
            isPaused: state.isPaused,
            isStopped: state.isStopped,
            isLoading: state.isLoading,
            onPlay: handlePlay,
            onPause: handlePause,
            onStop: handleStop,
            onSkip: handleSkip,
            onRestart: handleRestart
          }),
          React.createElement(PlayerView.VolumeControl, {
            volume: state.volume,
            onChange: handleVolumeChange
          })
        )
      ),
      React.createElement('div', { className: 'row mt-3' },
        React.createElement('div', { className: 'col-md-8' },
          React.createElement(PlayerView.QueuePanel, { queue: state.queue, onRemove: handleRemove, onPromote: handlePromote, onPlayNext: handlePlayNext }),
          React.createElement(PlayerView.HistoryPanel, {
            history: state.history,
            hasMore: state.historyHasMore,
            onLoadMore: handleLoadMoreHistory,
            onReRequest: handleReRequest
          })
        ),
        React.createElement('div', { className: 'col-md-4' },
          React.createElement(PlayerView.JoinPanel)
        )
      ),
      state.error && React.createElement(PlayerView.ErrorMessage, {
        error: state.error,
        onDismiss: () => setState(prev => ({ ...prev, error: null }))
      })
    );
  },

  // Current Song Display
  CurrentSongDisplay: function({ song }) {
    if (!song) {
      return React.createElement('div', { className: 'card mb-3' },
        React.createElement('div', { className: 'card-body text-center' },
          React.createElement('h5', { className: 'card-title' }, 'No Song Playing'),
          React.createElement('p', { className: 'card-text text-muted' }, 'Click play to start the jukebox')
        )
      );
    }

    return React.createElement('div', { className: 'card mb-3' },
      React.createElement('div', { className: 'card-body' },
        React.createElement('h5', { className: 'card-title' }, song.title),
        React.createElement('h6', { className: 'card-subtitle mb-2 text-muted' }, song.artist || 'Unknown Artist'),
        React.createElement('p', { className: 'card-text' },
          React.createElement('small', { className: 'text-muted' }, song.album || 'Unknown Album')
        ),
        React.createElement('p', { className: 'card-text' },
          React.createElement('small', { className: 'text-muted' },
            'Duration: ' + PlayerView.formatTime(song.duration)
          )
        )
      )
    );
  },

  // Progress Bar
  ProgressBar: function({ currentTime, duration }) {
    const progress = duration > 0 ? (currentTime / duration) * 100 : 0;

    return React.createElement('div', { className: 'progress mb-3', style: { height: '8px' } },
      React.createElement('div', { 
        className: 'progress-bar bg-primary', 
        role: 'progressbar', 
        style: { width: progress + '%' },
        'aria-valuenow': progress,
        'aria-valuemin': 0,
        'aria-valuemax': 100
      })
    );
  },

  // Player Controls
  Controls: function({ isPlaying, isPaused, isStopped, isLoading, onPlay, onPause, onStop, onSkip, onRestart }) {
    return React.createElement('div', { className: 'card mb-3' },
      React.createElement('div', { className: 'card-body' },
        React.createElement('h6', { className: 'card-title' }, 'Controls'),
        React.createElement('div', { className: 'd-flex justify-content-center gap-2 mb-3' },
          React.createElement('button', { 
            className: 'btn btn-outline-secondary btn-sm',
            onClick: onRestart,
            disabled: isLoading,
            title: 'Restart song (|<<)'
          }, React.createElement('i', { className: 'fas fa-step-backward' })),
          
          isPlaying ? 
            React.createElement('button', { 
              className: 'btn btn-warning btn-sm',
              onClick: onPause,
              disabled: isLoading,
              title: 'Pause'
            }, React.createElement('i', { className: 'fas fa-pause' })) :
            React.createElement('button', { 
              className: 'btn btn-success btn-sm',
              onClick: onPlay,
              disabled: isLoading,
              title: 'Play'
            }, React.createElement('i', { className: 'fas fa-play' })),
          
          React.createElement('button', { 
            className: 'btn btn-danger btn-sm',
            onClick: onStop,
            disabled: isLoading,
            title: 'Stop'
          }, React.createElement('i', { className: 'fas fa-stop' })),
          
          React.createElement('button', { 
            className: 'btn btn-outline-secondary btn-sm',
            onClick: onSkip,
            disabled: isLoading,
            title: 'Skip song (>>|)'
          }, React.createElement('i', { className: 'fas fa-step-forward' }))
        ),
        
        isLoading && React.createElement('div', { className: 'text-center' },
          React.createElement('div', { className: 'spinner-border spinner-border-sm text-primary', role: 'status' },
            React.createElement('span', { className: 'visually-hidden' }, 'Loading...')
          ),
          React.createElement('small', { className: 'ms-2 text-muted' }, 'Loading next song...')
        )
      )
    );
  },

  // Volume Control
  VolumeControl: function({ volume, onChange }) {
    return React.createElement('div', { className: 'card mb-3' },
      React.createElement('div', { className: 'card-body' },
        React.createElement('h6', { className: 'card-title' }, 'Volume'),
        React.createElement('div', { className: 'd-flex align-items-center' },
          React.createElement('i', { className: 'fas fa-volume-down me-2' }),
          React.createElement('input', { 
            type: 'range', 
            className: 'form-range flex-grow-1', 
            min: 0, 
            max: 1, 
            step: 0.1,
            value: volume,
            onChange: onChange
          }),
          React.createElement('i', { className: 'fas fa-volume-up ms-2' })
        ),
        React.createElement('small', { className: 'text-muted' }, Math.round(volume * 100) + '%')
      )
    );
  },

  // Error Message
  ErrorMessage: function({ error, onDismiss }) {
    return React.createElement('div', { className: 'alert alert-danger alert-dismissible fade show', role: 'alert' },
      React.createElement('strong', null, 'Error: '),
      error,
      React.createElement('button', { 
        type: 'button', 
        className: 'btn-close', 
        onClick: onDismiss,
        'aria-label': 'Close'
      })
    );
  },

  // Upcoming queue + incoming guest requests, with remove controls.
  QueuePanel: function({ queue, onRemove, onPromote, onPlayNext }) {
    const body = (!queue || queue.length === 0)
      ? React.createElement('p', { className: 'text-muted small mb-0' },
          'Queue is empty — random songs will fill in from the assigned playlists.')
      : React.createElement('ul', { className: 'list-group list-group-flush' },
          queue.map(function(item) {
            return React.createElement('li', {
              key: item.id,
              className: 'list-group-item d-flex justify-content-between align-items-center px-0'
            },
              React.createElement('div', { className: 'text-truncate me-2' },
                React.createElement('div', { className: 'text-truncate' }, item.song.title),
                React.createElement('small', { className: 'text-muted' }, item.song.artist || 'Unknown Artist')
              ),
              React.createElement('div', { className: 'd-flex align-items-center gap-1 flex-shrink-0' },
                item.source === 'requested'
                  ? React.createElement('span', { className: 'badge bg-success', title: 'Guest request' }, 'request')
                  : React.createElement('span', { className: 'badge bg-light text-muted', title: 'Auto-filled' }, 'auto'),
                React.createElement('button', {
                  className: 'btn btn-sm btn-outline-primary',
                  title: 'Play next',
                  onClick: function() { onPlayNext(item.song.id); }
                }, React.createElement('i', { className: 'fas fa-angles-up' })),
                item.source !== 'requested' && React.createElement('button', {
                  className: 'btn btn-sm btn-outline-secondary',
                  title: 'Move to request queue',
                  onClick: function() { onPromote(item.song.id); }
                }, React.createElement('i', { className: 'fas fa-arrow-up' })),
                React.createElement('button', {
                  className: 'btn btn-sm btn-outline-danger',
                  title: 'Remove from queue',
                  onClick: function() { onRemove(item.song.id); }
                }, React.createElement('i', { className: 'fas fa-times' }))
              )
            );
          })
        );

    return React.createElement('div', { className: 'card mb-3' },
      React.createElement('div', { className: 'card-body' },
        React.createElement('h6', { className: 'card-title' },
          'Up Next ',
          (queue && queue.length > 0) && React.createElement('span', { className: 'badge bg-secondary' }, queue.length)
        ),
        body
      )
    );
  },

  // Play history for this jukebox (most recent first), infinite-scrolling, with
  // a re-request ("play it again") button per song.
  HistoryPanel: function({ history, hasMore, onLoadMore, onReRequest }) {
    const handleScroll = function(e) {
      const el = e.target;
      if (hasMore && (el.scrollHeight - el.scrollTop - el.clientHeight) < 80) {
        onLoadMore();
      }
    };

    const rows = (!history || history.length === 0)
      ? React.createElement('p', { className: 'text-muted small mb-0' }, 'Nothing has played yet.')
      : React.createElement('ul', { className: 'list-group list-group-flush' },
          history.map(function(item) {
            return React.createElement('li', {
              key: item.id,
              className: 'list-group-item d-flex justify-content-between align-items-center px-0'
            },
              React.createElement('div', { className: 'text-truncate me-2' },
                React.createElement('div', { className: 'text-truncate' }, item.song.title),
                React.createElement('small', { className: 'text-muted' }, item.song.artist || 'Unknown Artist')
              ),
              React.createElement('div', { className: 'd-flex align-items-center gap-1 flex-shrink-0' },
                item.source === 'requested'
                  ? React.createElement('span', { className: 'badge bg-success', title: 'Guest request' }, 'request')
                  : React.createElement('span', { className: 'badge bg-light text-muted', title: 'Auto-filled' }, 'auto'),
                React.createElement('button', {
                  className: 'btn btn-sm btn-outline-primary',
                  title: 'Play again (re-add to queue)',
                  onClick: function() { onReRequest(item.song.id); }
                }, React.createElement('i', { className: 'fas fa-rotate-right' }))
              )
            );
          })
        );

    return React.createElement('div', { className: 'card mb-3' },
      React.createElement('div', { className: 'card-body' },
        React.createElement('h6', { className: 'card-title' }, 'Play History'),
        React.createElement('div', {
          style: { maxHeight: '320px', overflowY: 'auto' },
          onScroll: handleScroll
        },
          rows,
          hasMore && React.createElement('div', { className: 'text-center text-muted small py-2' }, 'Scroll for more…')
        )
      )
    );
  },

  // QR code + URL + password so guests can join from their phones.
  JoinPanel: function() {
    const cfg = window.AJB_CONFIG || {};
    const guestUrl = window.location.origin + '/jukeboxes/' + cfg.jukeboxId + '/guest';
    const qrRef = React.useRef(null);

    React.useEffect(function() {
      if (qrRef.current && typeof QRCode !== 'undefined') {
        qrRef.current.innerHTML = '';
        new QRCode(qrRef.current, {
          text: guestUrl,
          width: 180,
          height: 180,
          correctLevel: QRCode.CorrectLevel.M
        });
      }
    }, [guestUrl]);

    return React.createElement('div', { className: 'card mb-3' },
      React.createElement('div', { className: 'card-body text-center' },
        React.createElement('h6', { className: 'card-title' }, 'Guests: scan to join'),
        React.createElement('div', { ref: qrRef, className: 'd-inline-block p-2 bg-white rounded' }),
        React.createElement('div', { className: 'mt-2 text-truncate' },
          React.createElement('a', { href: guestUrl, target: '_blank', rel: 'noopener', className: 'small' }, guestUrl)
        ),
        cfg.hasPassword && React.createElement('div', { className: 'mt-2' },
          React.createElement('span', { className: 'text-muted small' }, 'Password: '),
          React.createElement('code', { className: 'fs-6' }, cfg.guestPassword)
        )
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