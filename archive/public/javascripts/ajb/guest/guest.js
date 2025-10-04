// Guest App - Main entry point for guest interface
// This is a React-based Single Page Application for guests

console.log('🎵 AJB Guest JavaScript loaded');

const { useState, useEffect } = React;

// Main Guest App Component
const GuestApp = () => {
  return React.createElement(GuestView.GuestApp);
};

// Mount the React app when DOM is ready
document.addEventListener('DOMContentLoaded', function() {
  console.log('DOM loaded, checking guest dependencies...');
  
  // Check if required libraries are loaded
  if (typeof React === 'undefined') {
    console.error('React is not loaded');
    document.getElementById('react-guest-app').innerHTML = '<div class="alert alert-danger">Error: React library not loaded</div>';
    return;
  }

  if (typeof ReactDOM === 'undefined') {
    console.error('ReactDOM is not loaded');
    document.getElementById('react-guest-app').innerHTML = '<div class="alert alert-danger">Error: ReactDOM library not loaded</div>';
    return;
  }

  if (typeof GuestController === 'undefined') {
    console.error('GuestController is not loaded');
    document.getElementById('react-guest-app').innerHTML = '<div class="alert alert-danger">Error: GuestController not loaded</div>';
    return;
  }

  if (typeof GuestView === 'undefined') {
    console.error('GuestView is not loaded');
    document.getElementById('react-guest-app').innerHTML = '<div class="alert alert-danger">Error: GuestView not loaded</div>';
    return;
  }

  if (typeof GuestApiService === 'undefined') {
    console.error('GuestApiService is not loaded');
    document.getElementById('react-guest-app').innerHTML = '<div class="alert alert-danger">Error: GuestApiService not loaded</div>';
    return;
  }

  if (typeof GuestState === 'undefined') {
    console.error('GuestState is not loaded');
    document.getElementById('react-guest-app').innerHTML = '<div class="alert alert-danger">Error: GuestState not loaded</div>';
    return;
  }

  // Check if guest config is available
  if (!window.AJB_GUEST_CONFIG || !window.AJB_GUEST_CONFIG.jukeboxId) {
    console.error('AJB_GUEST_CONFIG not found or missing jukeboxId');
    document.getElementById('react-guest-app').innerHTML = '<div class="alert alert-danger">Error: Guest configuration not found</div>';
    return;
  }

  console.log('All guest dependencies loaded successfully');
  console.log('Initializing AJB Guest with config:', window.AJB_GUEST_CONFIG);

  try {
    // Mount the React app
    const root = ReactDOM.createRoot(document.getElementById('react-guest-app'));
    root.render(React.createElement(GuestApp));
    console.log('Guest React app mounted successfully');
  } catch (error) {
    console.error('Error mounting guest React app:', error);
    document.getElementById('react-guest-app').innerHTML = '<div class="alert alert-danger">Error mounting guest React app: ' + error.message + '</div>';
  }
});
