// AJB Player App - Main entry point
// This is a React-based Single Page Application that runs entirely in the browser

// UPDATE CODE = 7
console.log('🎵 AJB Player JavaScript loaded - UPDATE CODE = 7');

const { useState, useEffect } = React;

// Main Player App Component
const PlayerApp = () => {
  return React.createElement(PlayerView.PlayerApp);
};

// Mount the React app when DOM is ready
document.addEventListener('DOMContentLoaded', function() {
  console.log('DOM loaded, checking dependencies...');
  
  // Check if required libraries are loaded
  if (typeof React === 'undefined') {
    console.error('React is not loaded');
    document.getElementById('react-player-app').innerHTML = '<div class="alert alert-danger">Error: React library not loaded</div>';
    return;
  }

  if (typeof ReactDOM === 'undefined') {
    console.error('ReactDOM is not loaded');
    document.getElementById('react-player-app').innerHTML = '<div class="alert alert-danger">Error: ReactDOM library not loaded</div>';
    return;
  }

  if (typeof Howl === 'undefined') {
    console.error('Howler.js is not loaded');
    document.getElementById('react-player-app').innerHTML = '<div class="alert alert-danger">Error: Howler.js library not loaded</div>';
    return;
  }

  if (typeof PlayerController === 'undefined') {
    console.error('PlayerController is not loaded');
    document.getElementById('react-player-app').innerHTML = '<div class="alert alert-danger">Error: PlayerController not loaded</div>';
    return;
  }

  if (typeof PlayerView === 'undefined') {
    console.error('PlayerView is not loaded');
    document.getElementById('react-player-app').innerHTML = '<div class="alert alert-danger">Error: PlayerView not loaded</div>';
    return;
  }

  // Check if AJB config is available
  if (!window.AJB_CONFIG || !window.AJB_CONFIG.jukeboxId) {
    console.error('AJB_CONFIG not found or missing jukeboxId');
    document.getElementById('react-player-app').innerHTML = '<div class="alert alert-danger">Error: AJB configuration not found</div>';
    return;
  }

  console.log('All dependencies loaded successfully');
  console.log('Initializing AJB Player with config:', window.AJB_CONFIG);

  try {
    // Mount the React app
    const root = ReactDOM.createRoot(document.getElementById('react-player-app'));
    root.render(React.createElement(PlayerApp));
    console.log('React app mounted successfully');
  } catch (error) {
    console.error('Error mounting React app:', error);
    document.getElementById('react-player-app').innerHTML = '<div class="alert alert-danger">Error mounting React app: ' + error.message + '</div>';
  }
});