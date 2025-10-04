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
      error: null
    });

    const [controller, setController] = React.useState(null);

    // Initialize controller on mount
    React.useEffect(() => {
      console.log('🔍 PlayerView useEffect - Starting initialization...');
      console.log('🔍 window.AJB_CONFIG:', window.AJB_CONFIG);
      console.log('🔍 jukeboxId present:', !!window.AJB_CONFIG?.jukeboxId);
      console.log('🔍 apiToken present:', !!window.AJB_CONFIG?.apiToken);
      console.log('🔍 apiToken value:', window.AJB_CONFIG?.apiToken);
      
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
          const playerController = new PlayerController(window.AJB_CONFIG.jukeboxId, window.AJB_CONFIG.apiToken);
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

  // Utility function to format time
  formatTime: function(seconds) {
    if (!seconds || isNaN(seconds)) return '0:00';
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return mins + ':' + secs.toString().padStart(2, '0');
  }
};