// Guest View - React components for the guest interface
// VERSION 2.0 - Fixed focus preservation and debouncing
const GuestView = {
  // Main Guest App Component
  GuestApp: function() {
    console.log('🔍 GuestApp component rendering/re-rendering');
    
    const [state, setState] = React.useState(() => {
      console.log('🔍 GuestApp useState initializer called');
      return {
        authenticated: false,
        loading: false,
        error: null,
        currentView: 'auth'
      };
    });

    const [controller, setController] = React.useState(() => {
      console.log('🔍 GuestApp controller useState initializer called');
      return null;
    });

    // Track component lifecycle
    React.useEffect(() => {
      console.log('🔍 GuestApp component mounted');
      return () => {
        console.log('🔍 GuestApp component unmounting');
      };
    }, []);

    // Track re-renders
    React.useEffect(() => {
      console.log('🔍 GuestApp re-rendered');
      console.log('🔍 GuestApp current state:', state);
      console.log('🔍 GuestApp controller exists:', !!controller);
    });

    // Initialize controller on mount
    React.useEffect(() => {
      if (window.AJB_GUEST_CONFIG && window.AJB_GUEST_CONFIG.jukeboxId) {
        const guestController = new GuestController(
          window.AJB_GUEST_CONFIG.jukeboxId,
          window.AJB_GUEST_CONFIG.password
        );
        
        setController(guestController);
        
        // Subscribe to state changes - only update when relevant fields change
        const unsubscribe = guestController.state.subscribe((newState) => {
          console.log('🔍 GuestApp state subscription callback triggered');
          console.log('🔍 GuestApp newState:', newState);
          console.log('🔍 GuestApp newState.searchResults.length:', newState?.searchResults?.length || 0);
          console.log('🔍 GuestApp newState.searchQuery:', newState?.searchQuery);
          console.log('🔍 GuestApp newState.searchLoading:', newState?.searchLoading);
          
          setState(prev => {
            console.log('🔍 GuestApp setState called with prev state:', prev);
            
            // Only update if something actually changed that affects the UI
            const newStateToSet = {
              ...prev,
              authenticated: newState.authenticated,
              loading: newState.loading,
              error: newState.error,
              currentView: newState.currentView,
              currentSong: newState.currentSong,
              currentPosition: newState.currentPosition,
              isPlaying: newState.isPlaying,
              volume: newState.volume,
              queue: newState.queue,
              totalQueueCount: newState.totalQueueCount,
              jukeboxName: newState.jukeboxName,
              jukeboxStatus: newState.jukeboxStatus,
              searchResults: newState.searchResults,
              searchQuery: newState.searchQuery,
              searchLoading: newState.searchLoading
            };
            
            // Check if anything actually changed
            const hasChanges = Object.keys(newStateToSet).some(key => {
              return JSON.stringify(prev[key]) !== JSON.stringify(newStateToSet[key]);
            });
            
            if (!hasChanges) {
              console.log('🔍 GuestApp no actual changes, skipping state update');
              return prev; // Return same state to prevent re-render
            }
            
            console.log('🔍 GuestApp new state to set:', newStateToSet);
            return newStateToSet;
          });
        });

        return () => {
          unsubscribe();
          if (guestController) {
            guestController.destroy();
          }
        };
      }
    }, []);

    // Handle authentication
    const handleAuthenticate = async () => {
      if (controller) {
        await controller.authenticate();
      }
    };

    // Handle view switching
    const switchToNowPlaying = () => controller && controller.switchToNowPlaying();
    const switchToRequestSongs = () => controller && controller.switchToRequestSongs();

    if (!controller) {
      return React.createElement('div', { className: 'text-center p-4' },
        React.createElement('div', { className: 'spinner-border text-primary', role: 'status' },
          React.createElement('span', { className: 'visually-hidden' }, 'Loading...')
        ),
        React.createElement('p', { className: 'mt-3' }, 'Initializing guest interface...')
      );
    }

    if (!state.authenticated) {
      return React.createElement(GuestView.AuthView, {
        onAuthenticate: handleAuthenticate,
        loading: state.loading,
        error: state.error
      });
    }

    return React.createElement('div', { className: 'guest-app' },
      React.createElement(GuestView.Header, {
        currentView: state.currentView,
        onSwitchToNowPlaying: switchToNowPlaying,
        onSwitchToRequestSongs: switchToRequestSongs
      }),
      state.currentView === 'now-playing' ?
        React.createElement(GuestView.NowPlayingView, { controller, state }) :
        React.createElement(GuestView.RequestSongsView, { controller, state }),
      state.error && React.createElement(GuestView.ErrorMessage, {
        error: state.error,
        onDismiss: () => controller && controller.state.clearError()
      })
    );
  },

  // Authentication View
  AuthView: function({ onAuthenticate, loading, error }) {
    const [password, setPassword] = React.useState('');

    const handleSubmit = (e) => {
      e.preventDefault();
      if (window.AJB_GUEST_CONFIG) {
        window.AJB_GUEST_CONFIG.password = password;
        onAuthenticate();
      }
    };

    return React.createElement('div', { className: 'auth-container' },
      React.createElement('div', { className: 'row justify-content-center' },
        React.createElement('div', { className: 'col-md-6' },
          React.createElement('div', { className: 'card' },
            React.createElement('div', { className: 'card-body text-center' },
              React.createElement('h2', { className: 'card-title mb-4' }, '🎵 Join Jukebox'),
              React.createElement('p', { className: 'card-text mb-4' },
                'Enter the jukebox password to join and see what\'s playing'
              ),
              React.createElement('form', { onSubmit: handleSubmit },
                React.createElement('div', { className: 'mb-3' },
                  React.createElement('input', {
                    type: 'password',
                    className: 'form-control',
                    placeholder: 'Jukebox Password',
                    value: password,
                    onChange: (e) => setPassword(e.target.value),
                    required: true,
                    disabled: loading
                  })
                ),
                React.createElement('button', {
                  type: 'submit',
                  className: 'btn btn-primary btn-lg w-100',
                  disabled: loading
                }, loading ? 'Connecting...' : 'Join Jukebox')
              ),
              error && React.createElement('div', { className: 'alert alert-danger mt-3' },
                error
              )
            )
          )
        )
      )
    );
  },

  // Header with navigation
  Header: function({ currentView, onSwitchToNowPlaying, onSwitchToRequestSongs }) {
    return React.createElement('div', { className: 'guest-header mb-4' },
      React.createElement('nav', { className: 'navbar navbar-expand-lg navbar-dark bg-primary' },
        React.createElement('div', { className: 'container-fluid' },
          React.createElement('span', { className: 'navbar-brand mb-0 h1' }, '🎵 Guest View'),
          React.createElement('div', { className: 'navbar-nav ms-auto' },
            React.createElement('button', {
              className: `nav-link btn btn-link ${currentView === 'now-playing' ? 'active' : ''}`,
              onClick: onSwitchToNowPlaying
            }, 'Now Playing'),
            React.createElement('button', {
              className: `nav-link btn btn-link ${currentView === 'request-songs' ? 'active' : ''}`,
              onClick: onSwitchToRequestSongs
            }, 'Request Songs')
          )
        )
      )
    );
  },

  // Now Playing View
  NowPlayingView: function({ controller, state }) {
    React.useEffect(() => {
      // Load initial data
      controller.updatePlaybackInfo();
      controller.updateQueue();
    }, [controller]);

    return React.createElement('div', { className: 'now-playing-view' },
      React.createElement('div', { className: 'row' },
        React.createElement('div', { className: 'col-md-6' },
          React.createElement(GuestView.CurrentSongDisplay, { song: state.currentSong }),
          React.createElement(GuestView.ProgressBar, {
            currentTime: parseFloat(state.currentPosition) || 0,
            duration: state.currentSong?.duration || 0,
            isPlaying: state.isPlaying
          })
        ),
        React.createElement('div', { className: 'col-md-6' },
          React.createElement(GuestView.QueueDisplay, { queue: state.queue })
        )
      )
    );
  },

  // Current Song Display
  CurrentSongDisplay: function({ song }) {
    if (!song) {
      return React.createElement('div', { className: 'card mb-3' },
        React.createElement('div', { className: 'card-body text-center' },
          React.createElement('h5', { className: 'card-title' }, 'No Song Playing'),
          React.createElement('p', { className: 'card-text text-muted' }, 'Waiting for music to start...')
        )
      );
    }

    return React.createElement('div', { className: 'card mb-3' },
      React.createElement('div', { className: 'card-body' },
        React.createElement('h5', { className: 'card-title' }, song.title || 'Unknown Title'),
        React.createElement('h6', { className: 'card-subtitle mb-2 text-muted' }, 
          song.artist || 'Unknown Artist'
        ),
        React.createElement('p', { className: 'card-text' },
          React.createElement('small', { className: 'text-muted' }, 
            song.album || 'Unknown Album'
          )
        ),
        React.createElement('p', { className: 'card-text' },
          React.createElement('small', { className: 'text-muted' },
            `Duration: ${GuestState.formatTime(song.duration || 0)}`
          )
        )
      )
    );
  },

  // Progress Bar
  ProgressBar: function({ currentTime, duration, isPlaying }) {
    const progress = duration > 0 ? (currentTime / duration) * 100 : 0;
    const timeRemaining = Math.max(duration - currentTime, 0);

    return React.createElement('div', { className: 'progress-container mb-3' },
      React.createElement('div', { className: 'progress mb-2', style: { height: '10px' } },
        React.createElement('div', {
          className: `progress-bar ${isPlaying ? 'bg-success' : 'bg-secondary'}`,
          role: 'progressbar',
          style: { width: `${progress}%` },
          'aria-valuenow': progress,
          'aria-valuemin': 0,
          'aria-valuemax': 100
        })
      ),
      React.createElement('div', { className: 'd-flex justify-content-between' },
        React.createElement('small', { className: 'text-muted' },
          GuestState.formatTime(currentTime)
        ),
        React.createElement('small', { className: 'text-muted' },
          `-${GuestState.formatTime(timeRemaining)}`
        )
      )
    );
  },

  // Queue Display
  QueueDisplay: function({ queue }) {
    return React.createElement('div', { className: 'card' },
      React.createElement('div', { className: 'card-header d-flex justify-content-between align-items-center' },
        React.createElement('h6', { className: 'card-title mb-0' }, 'Upcoming Songs'),
        React.createElement('span', { className: 'badge bg-primary' }, queue.length)
      ),
      React.createElement('div', { className: 'card-body p-0' },
        queue.length === 0 ?
          React.createElement('div', { className: 'p-3 text-center text-muted' },
            'No songs in queue'
          ) :
          React.createElement('div', { 
            className: 'list-group list-group-flush',
            style: { 
              maxHeight: '400px', 
              overflowY: 'auto' 
            }
          },
            queue.map((item, index) =>
              React.createElement('div', {
                key: `${item.song.id}-${index}`,
                className: `list-group-item ${item.source === 'requested' ? 'list-group-item-warning' : ''}`,
                style: { fontSize: '0.9em' }
              },
                React.createElement('div', { className: 'd-flex justify-content-between align-items-start' },
                  React.createElement('div', { className: 'flex-grow-1' },
                    React.createElement('h6', { className: 'mb-1', style: { fontSize: '1em' } }, item.song.title),
                    React.createElement('p', { className: 'mb-1 text-muted', style: { fontSize: '0.85em' } },
                      item.song.artist || 'Unknown Artist'
                    ),
                    React.createElement('small', { className: 'text-muted', style: { fontSize: '0.8em' } },
                      GuestState.formatTime(item.song.duration || 0)
                    )
                  ),
                  React.createElement('div', { className: 'd-flex flex-column align-items-end' },
                    React.createElement('span', { className: 'badge bg-secondary mb-1', style: { fontSize: '0.7em' } },
                      item.source === 'requested' ? 'Requested' : 'Random'
                    ),
                    React.createElement('small', { className: 'text-muted', style: { fontSize: '0.75em' } },
                      `#${item.position}`
                    )
                  )
                )
              )
            )
          )
      )
    );
  },


  // Request Songs View
  RequestSongsView: function({ controller, state }) {
    console.log('🔍 RequestSongsView component rendering/re-rendering');
    console.log('🔍 RequestSongsView state:', {
      searchResults: state?.searchResults?.length || 0,
      searchLoading: state?.searchLoading,
      searchQuery: state?.searchQuery,
      currentView: state?.currentView
    });
    
    const handleRequestSong = (song) => {
      console.log('🔍 RequestSongsView handleRequestSong called for song:', song.id);
      controller.requestSong(song.id);
    };

    // Initialize static search input after component mounts
    React.useEffect(() => {
      console.log('🔍 RequestSongsView component mounted - initializing static search');
      initializeStaticSearch(controller);
      
      return () => {
        console.log('🔍 RequestSongsView component unmounting');
        cleanupStaticSearch();
      };
    }, [controller]);

    // Track component lifecycle
    React.useEffect(() => {
      console.log('🔍 RequestSongsView component mounted');
      return () => {
        console.log('🔍 RequestSongsView component unmounting');
      };
    }, []);

    // Track re-renders
    React.useEffect(() => {
      console.log('🔍 RequestSongsView re-rendered');
    });

    return React.createElement('div', { className: 'request-songs-view' },
      React.createElement('div', { className: 'row' },
        React.createElement('div', { className: 'col-12' },
          React.createElement('div', { className: 'card mb-4' },
            React.createElement('div', { className: 'card-body' },
              React.createElement('h5', { className: 'card-title' }, 'Request a Song'),
              React.createElement('p', { className: 'card-text text-muted' },
                'Search for songs and click to add them to the queue. Requested songs will play before random songs.'
              ),
              // Static search input container - React never touches the input element
              React.createElement('div', { 
                id: 'static-search-container',
                className: 'mb-3' 
              })
            )
          ),
          // Search results - only this part updates when results change
          React.createElement(GuestView.SearchResultsContainer, {
            key: 'search-results', // Key ensures proper re-rendering
            results: state.searchResults,
            loading: state.searchLoading,
            pagination: state.searchPagination,
            onRequestSong: handleRequestSong
          })
        )
      )
    );
  },

  // Search Results Container - only updates when results change
  SearchResultsContainer: React.memo(function({ results, loading, pagination, onRequestSong }) {
    console.log('🔍 SearchResultsContainer rendering - results count:', results.length, 'loading:', loading);
    
    // Only render if we have results or are loading
    if (results.length === 0 && !loading) {
      return null;
    }

    return React.createElement(GuestView.SearchResults, {
      results: results,
      onRequestSong: onRequestSong,
      loading: loading,
      pagination: pagination
    });
  }, function(prevProps, nextProps) {
    // Only re-render if results, loading, or pagination actually changed
    const resultsChanged = prevProps.results.length !== nextProps.results.length;
    const loadingChanged = prevProps.loading !== nextProps.loading;
    const paginationChanged = JSON.stringify(prevProps.pagination) !== JSON.stringify(nextProps.pagination);
    
    const shouldUpdate = resultsChanged || loadingChanged || paginationChanged;
    console.log('🔍 SearchResultsContainer memo comparison:', {
      resultsChanged,
      loadingChanged,
      paginationChanged,
      shouldUpdate
    });
    
    return !shouldUpdate; // Return true to skip re-render, false to re-render
  }),

  // Search Results
  SearchResults: function({ results, onRequestSong, loading, pagination }) {
    return React.createElement('div', { className: 'card' },
      React.createElement('div', { className: 'card-header d-flex justify-content-between align-items-center' },
        React.createElement('h6', { className: 'card-title mb-0' }, 'Search Results'),
        pagination && React.createElement('span', { className: 'badge bg-secondary' }, 
          `${results.length} of ${pagination.total_count} songs`
        )
      ),
      loading && React.createElement('div', { className: 'card-body text-center' },
        React.createElement('div', { className: 'spinner-border spinner-border-sm text-primary', role: 'status' },
          React.createElement('span', { className: 'visually-hidden' }, 'Searching...')
        ),
        React.createElement('small', { className: 'ms-2 text-muted' }, 'Searching...')
      ),
      !loading && React.createElement('div', { className: 'card-body p-0' },
        results.length === 0 ?
          React.createElement('div', { className: 'p-3 text-center text-muted' },
            'No songs found. Try different search terms.'
          ) :
          React.createElement('div', { 
            className: 'list-group list-group-flush',
            style: { 
              maxHeight: '500px', 
              overflowY: 'auto' 
            }
          },
            results.map((song) =>
              React.createElement('div', {
                key: song.id,
                className: 'list-group-item list-group-item-action',
                onClick: () => onRequestSong(song),
                style: { fontSize: '0.9em' }
              },
                React.createElement('div', { className: 'd-flex justify-content-between align-items-start' },
                  React.createElement('div', { className: 'flex-grow-1' },
                    React.createElement('h6', { className: 'mb-1', style: { fontSize: '1em' } }, song.title),
                    React.createElement('p', { className: 'mb-1 text-muted', style: { fontSize: '0.85em' } },
                      song.artist || 'Unknown Artist'
                    ),
                    React.createElement('small', { className: 'text-muted', style: { fontSize: '0.8em' } },
                      song.album ? `${song.album} • ` : '',
                      song.genre ? `${song.genre} • ` : '',
                      GuestState.formatTime(song.duration || 0)
                    )
                  ),
                  React.createElement('button', {
                    className: 'btn btn-sm btn-outline-primary',
                    onClick: (e) => {
                      e.stopPropagation();
                      onRequestSong(song);
                    },
                    style: { fontSize: '0.8em' }
                  }, 'Request')
                )
              )
            )
          )
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
  }
};

// Static search input - completely outside React tree
let staticSearchTimeout = null;

function initializeStaticSearch(controller) {
  console.log('🔍 Initializing static search - VERSION 2.0');
  
  const container = document.getElementById('static-search-container');
  if (!container) {
    console.error('Static search container not found');
    return;
  }

  // Create static HTML that React never touches
  container.innerHTML = `
    <div class="input-group">
      <input 
        id="static-search-input" 
        type="text" 
        class="form-control" 
        placeholder="Search for songs, artists, or albums... (type to search)"
      />
      <button 
        id="static-clear-search" 
        type="button" 
        class="btn btn-outline-secondary" 
        style="display: none;" 
        title="Clear search"
      >
        <i class="fas fa-times"></i>
      </button>
    </div>
    <small class="text-muted">
      Type any words from song title, artist, album, or genre. More words = fewer results.
    </small>
  `;

  const searchInput = document.getElementById('static-search-input');
  const clearBtn = document.getElementById('static-clear-search');

  // Search handler with proper debouncing
  const handleSearch = (e) => {
    const query = e.target.value.trim();
    console.log('🔍 Static search handler called with query:', query);
    
    // Clear existing timeout
    if (staticSearchTimeout) {
      clearTimeout(staticSearchTimeout);
    }

    // Show/hide clear button
    clearBtn.style.display = query ? 'block' : 'none';

    // Set new timeout for search (500ms debounce)
    if (query) {
      staticSearchTimeout = setTimeout(() => {
        console.log('🔍 Static search timeout fired, calling controller.searchSongs');
        controller.searchSongs(query);
      }, 500);
    } else {
      console.log('🔍 Static search clearing results (empty query)');
      controller.state.setSearchResults([], null, '');
    }
  };

  // Clear handler
  const handleClear = () => {
    console.log('🔍 Static search clear handler called');
    searchInput.value = '';
    searchInput.focus();
    handleSearch({ target: searchInput });
  };

  // Add event listeners
  searchInput.addEventListener('input', handleSearch);
  clearBtn.addEventListener('click', handleClear);

  console.log('🔍 Static search initialized successfully - VERSION 2.0');
}

function cleanupStaticSearch() {
  console.log('🔍 Cleaning up static search');
  if (staticSearchTimeout) {
    clearTimeout(staticSearchTimeout);
    staticSearchTimeout = null;
  }
}
