// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "htmx.org"

// Bootstrap JavaScript (if needed beyond the CDN)
// import "bootstrap"

// Custom JavaScript for the music archive
document.addEventListener('turbo:load', function() {
  // Initialize any custom JavaScript here
  console.log('Music Archive loaded');
}); 