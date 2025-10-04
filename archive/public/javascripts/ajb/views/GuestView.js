// Guest View - React components for the guest interface
const GuestView = {
  // Main Guest Component
  GuestApp: () => {
    const [controller, setController] = React.useState(null);
    const [playbackInfo, setPlaybackInfo] = React.useState(null);
    const [queue, setQueue] = React.useState([]);
    const [searchResults, setSearchResults] = React.useState([]);
    const [connectionStatus, setConnectionStatus] = React.useState('connecting');
    const [isInitialized, setIsInitialized] = React.useState(false);
    const [error, setError] = React.useState(null);

    // Initialize controller
    React.useEffect(() => {
      const initController = async () => {
        try {
          const guestController = new GuestController(window.AJB_CONFIG);
          await guestController.initialize();
          
          setController(guestController);
          setPlaybackInfo(guestController.getCurrentPlaybackInfo());
          setQueue(guestController.getQueue());
          setIsInitialized(true);

          // Subscribe to real-time updates
          guestController.addEventListener('playbackUpdate', (data) => {
            setPlaybackInfo(data);
          });

          guestController.addEventListener('queueUpdate', (data) => {
            setQueue(data);
          });

          guestController.addEventListener('searchResults', (data) => {
            setSearchResults(data);
          });

          guestController.addEventListener('connectionStatus', (status) => {
            setConnectionStatus(status);
          });

        } catch (error) {
          console.error('Failed to initialize guest controller:', error);
          setError(error.message);
        }
      };

      initController();
    }, []);

    // Cleanup on unmount
    React.useEffect(() => {
      return () => {
        if (controller) {
          controller.destroy();
        }
      };
    }, [controller]);

    if (error) {
      return (
        <div className="alert alert-danger">
          <h5>Connection Error</h5>
          <p>{error}</p>
          <button 
            className="btn btn-primary" 
            onClick={() => window.location.reload()}
          >
            Retry
          </button>
        </div>
      );
    }

    if (!isInitialized) {
      return (
        <div className="text-center">
          <div className="spinner-border text-primary" role="status">
            <span className="visually-hidden">Loading...</span>
          </div>
          <p className="mt-3">Connecting to jukebox...</p>
        </div>
      );
    }

    return (
      <div className="container-fluid">
        <div className="row">
          <div className="col-12">
            <GuestView.StatusCard playbackInfo={playbackInfo} connectionStatus={connectionStatus} />
            <GuestView.CurrentSongCard playbackInfo={playbackInfo} />
            <GuestView.SearchCard controller={controller} searchResults={searchResults} />
            <GuestView.QueueCard queue={queue} />
            <GuestView.SessionInfoCard config={window.AJB_CONFIG} />
          </div>
        </div>
      </div>
    );
  },

  // Status Card Component
  StatusCard: ({ playbackInfo, connectionStatus }) => (
    <div className="card mb-3">
      <div className="card-header bg-info text-white">
        <h5 className="mb-0">
          <i className="fas fa-users me-2"></i>
          AJB Guest Controller - {window.AJB_CONFIG.jukeboxName}
        </h5>
        <small>Session: {window.AJB_CONFIG.sessionId}</small>
        <div className="mt-2">
          <span className={`badge ${connectionStatus === 'connected' ? 'bg-success' : 'bg-warning'}`}>
            <i className={`fas fa-${connectionStatus === 'connected' ? 'wifi' : 'exclamation-triangle'} me-1`}></i>
            {connectionStatus === 'connected' ? 'Connected' : 'Connecting...'}
          </span>
        </div>
      </div>
      <div className="card-body">
        <div className="row">
          <div className="col-md-6">
            <p><strong>Status:</strong> 
              <span className={`badge bg-${playbackInfo?.is_playing ? 'success' : 'secondary'} ms-2`}>
                {playbackInfo?.is_playing ? 'Playing' : 'Stopped'}
              </span>
            </p>
            <p><strong>Queue:</strong> {window.guestQueue?.length || 0} songs</p>
          </div>
          <div className="col-md-6">
            <p><strong>Volume:</strong> {Math.round((playbackInfo?.volume || 0.8) * 100)}%</p>
            <p><strong>Last Update:</strong> 
              {playbackInfo?.last_update ? new Date(playbackInfo.last_update).toLocaleTimeString() : 'Never'}
            </p>
          </div>
        </div>
      </div>
    </div>
  ),

  // Current Song Card Component
  CurrentSongCard: ({ playbackInfo }) => (
    <div className="card mb-3">
      <div className="card-header">
        <h5 className="mb-0">Now Playing</h5>
      </div>
      <div className="card-body">
        {playbackInfo?.current_song ? (
          <div className="d-flex align-items-center">
            <div className="flex-grow-1">
              <h6 className="mb-1">{playbackInfo.current_song.title}</h6>
              <p className="mb-1 text-muted">
                {playbackInfo.current_song.artist} - {playbackInfo.current_song.album}
              </p>
              <div className="progress mb-2" style={{ height: '4px' }}>
                <div 
                  className="progress-bar bg-primary" 
                  style={{ 
                    width: `${((playbackInfo.position || 0) / (playbackInfo.current_song.duration || 1)) * 100}%` 
                  }}
                ></div>
              </div>
              <small className="text-muted">
                {Math.floor((playbackInfo.position || 0) / 60)}:{(Math.floor(playbackInfo.position || 0) % 60).toString().padStart(2, '0')} / 
                {Math.floor(playbackInfo.current_song.duration / 60)}:{(playbackInfo.current_song.duration % 60).toString().padStart(2, '0')}
              </small>
            </div>
            <div className="ms-3">
              <i className="fas fa-music fa-2x text-info"></i>
            </div>
          </div>
        ) : (
          <p className="text-muted mb-0">No song playing</p>
        )}
      </div>
    </div>
  ),

  // Search Card Component
  SearchCard: ({ controller, searchResults }) => {
    const [searchQuery, setSearchQuery] = React.useState('');
    const [isSearching, setIsSearching] = React.useState(false);

    const handleSearch = async (e) => {
      e.preventDefault();
      if (!searchQuery.trim() || !controller) return;

      setIsSearching(true);
      try {
        await controller.searchSongs(searchQuery);
      } finally {
        setIsSearching(false);
      }
    };

    const handleRequestSong = async (song) => {
      if (!controller) return;

      try {
        await controller.requestSong(song.id, 'Guest');
        alert(`Requested: ${song.title} by ${song.artist}`);
      } catch (error) {
        alert('Failed to request song: ' + error.message);
      }
    };

    return (
      <div className="card mb-3">
        <div className="card-header">
          <h5 className="mb-0">Request Songs</h5>
        </div>
        <div className="card-body">
          <form onSubmit={handleSearch}>
            <div className="input-group">
              <input
                type="text"
                className="form-control"
                placeholder="Search for songs..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
              />
              <button 
                className="btn btn-outline-primary" 
                type="submit"
                disabled={isSearching}
              >
                {isSearching ? (
                  <>
                    <span className="spinner-border spinner-border-sm me-1" role="status"></span>
                    Searching...
                  </>
                ) : (
                  <>
                    <i className="fas fa-search me-1"></i>
                    Search
                  </>
                )}
              </button>
            </div>
          </form>
          
          {/* Search Results */}
          {searchResults.length > 0 && (
            <div className="mt-3">
              <h6>Search Results</h6>
              <div className="list-group">
                {searchResults.map((song) => (
                  <div key={song.id} className="list-group-item d-flex justify-content-between align-items-center">
                    <div>
                      <h6 className="mb-1">{song.title}</h6>
                      <p className="mb-1 text-muted">{song.artist} - {song.album}</p>
                    </div>
                    <button 
                      className="btn btn-sm btn-success"
                      onClick={() => handleRequestSong(song)}
                    >
                      <i className="fas fa-plus me-1"></i>
                      Request
                    </button>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>
    );
  },

  // Queue Card Component
  QueueCard: ({ queue }) => (
    <div className="card mb-3">
      <div className="card-header">
        <h5 className="mb-0">Queue ({queue.length} songs)</h5>
      </div>
      <div className="card-body">
        {queue.length > 0 ? (
          <div className="list-group">
            {queue.slice(0, 10).map((item, index) => (
              <div key={item.id} className="list-group-item">
                <div className="d-flex w-100 justify-content-between">
                  <h6 className="mb-1">#{index + 1} {item.song.title}</h6>
                  <small>{item.song.duration ? Math.floor(item.song.duration / 60) + ':' + (item.song.duration % 60).toString().padStart(2, '0') : ''}</small>
                </div>
                <p className="mb-1 text-muted">
                  {item.song.artist}
                  {item.requested_by && (
                    <span className="text-info"> - Requested by {item.requested_by}</span>
                  )}
                </p>
              </div>
            ))}
            {queue.length > 10 && (
              <div className="list-group-item text-center text-muted">
                ... and {queue.length - 10} more songs
              </div>
            )}
          </div>
        ) : (
          <p className="text-muted mb-0">Queue is empty</p>
        )}
      </div>
    </div>
  ),

  // Session Info Card Component
  SessionInfoCard: ({ config }) => (
    <div className="card mb-3">
      <div className="card-header">
        <h5 className="mb-0">Session Information</h5>
      </div>
      <div className="card-body">
        <div className="row">
          <div className="col-md-6">
            <small className="text-muted">
              <strong>Jukebox:</strong> {config.jukeboxName}<br/>
              <strong>Status:</strong> {config.status}<br/>
              <strong>Private:</strong> {config.private ? 'Yes' : 'No'}
            </small>
          </div>
          <div className="col-md-6">
            <small className="text-muted">
              <strong>Session ID:</strong> {config.sessionId}<br/>
              <strong>Password Protected:</strong> {config.hasPassword ? 'Yes' : 'No'}
            </small>
          </div>
        </div>
      </div>
    </div>
  )
};
