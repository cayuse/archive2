// AJB Guest App - Main entry point
// Load all required modules
const { useState, useEffect } = React;

// Import all our modules (they're loaded via script tags in the HTML)
// GuestController, WebSocketService, ApiService, GuestView

// Main Guest App Component
const GuestApp = () => {
  return <GuestView.GuestApp />;
};

// Mount the React app
const root = ReactDOM.createRoot(document.getElementById('react-guest-app'));
root.render(<GuestApp />);