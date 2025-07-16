// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "htmx.org"
import Sortable from "sortablejs"

// Bootstrap JavaScript (if needed beyond the CDN)
// import "bootstrap"

// Test function to verify JavaScript is loading
window.testJavaScript = function() {
  console.log('JavaScript is loaded and working!');
  alert('JavaScript is working!');
};

// Test function for playlist functions
window.testPlaylistFunctions = function() {
  console.log('Testing playlist functions...');
  console.log('addSelectedSongsToPlaylist:', typeof window.addSelectedSongsToPlaylist);
  console.log('showCreatePlaylistModal:', typeof window.showCreatePlaylistModal);
  
  if (typeof window.addSelectedSongsToPlaylist === 'function') {
    console.log('✅ addSelectedSongsToPlaylist is available');
  } else {
    console.log('❌ addSelectedSongsToPlaylist is NOT available');
  }
  
  if (typeof window.showCreatePlaylistModal === 'function') {
    console.log('✅ showCreatePlaylistModal is available');
  } else {
    console.log('❌ showCreatePlaylistModal is NOT available');
  }
  
  alert('Check console for playlist function test results');
};

// Global playlist functions (accessible from onclick handlers)
window.addSelectedSongsToPlaylist = function(playlistId, playlistName) {
  console.log('addSelectedSongsToPlaylist called with:', playlistId, playlistName);
  
  const selectedSongs = document.querySelectorAll('.song-select-checkbox:checked');
  const songIds = Array.from(selectedSongs).map(checkbox => checkbox.value);
  
  if (songIds.length === 0) {
    alert('Please select at least one song to add to the playlist.');
    return;
  }
  
  console.log(`Adding ${songIds.length} songs to playlist: ${playlistName}`);
  
  // Use fetch instead of HTMX for better control
  fetch(`/playlists/${playlistId}/add_songs`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
      'X-Requested-With': 'XMLHttpRequest'
    },
    body: JSON.stringify({ song_ids: songIds })
  })
  .then(response => response.json())
  .then(data => {
    if (data.success) {
      // Show success message
      const message = `${data.message} (${songIds.length} songs added to "${data.playlist_name}")`;
      showNotification(message, 'success');
      
      // Clear selections
      selectedSongs.forEach(checkbox => checkbox.checked = false);
      updatePlaylistButtonState();
      updateSelectAllCheckbox();
    } else {
      showNotification(data.error || 'Failed to add songs to playlist', 'error');
    }
  })
  .catch(error => {
    console.error('Error adding songs to playlist:', error);
    showNotification('Error adding songs to playlist', 'error');
  });
};

window.showCreatePlaylistModal = function() {
  console.log('showCreatePlaylistModal called');
  
  const playlistName = prompt('Enter playlist name:');
  if (playlistName && playlistName.trim()) {
    const selectedSongs = document.querySelectorAll('.song-select-checkbox:checked');
    const songIds = Array.from(selectedSongs).map(checkbox => checkbox.value);
    
    if (songIds.length === 0) {
      alert('Please select at least one song to add to the new playlist.');
      return;
    }
    
    console.log(`Creating new playlist "${playlistName}" with ${songIds.length} songs`);
    
    // Create playlist and add songs
    fetch('/playlists', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
        'X-Requested-With': 'XMLHttpRequest'
      },
      body: JSON.stringify({ 
        playlist: { name: playlistName.trim(), is_public: false },
        song_ids: songIds 
      })
    })
    .then(response => {
      if (response.redirected) {
        // Redirect to the new playlist
        window.location.href = response.url;
      } else {
        return response.json();
      }
    })
    .then(data => {
      if (data && data.success) {
        showNotification(`Created playlist "${playlistName}" with ${songIds.length} songs`, 'success');
        
        // Clear selections
        selectedSongs.forEach(checkbox => checkbox.checked = false);
        updatePlaylistButtonState();
        updateSelectAllCheckbox();
      } else if (data) {
        showNotification(data.error || 'Failed to create playlist', 'error');
      }
    })
    .catch(error => {
      console.error('Error creating playlist:', error);
      showNotification('Error creating playlist', 'error');
    });
  }
};

window.showNotification = function(message, type = 'info') {
  // Create a simple notification
  const notification = document.createElement('div');
  notification.className = `alert alert-${type === 'success' ? 'success' : 'danger'} alert-dismissible fade show position-fixed`;
  notification.style.cssText = 'top: 20px; right: 20px; z-index: 9999; min-width: 300px;';
  notification.innerHTML = `
    ${message}
    <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
  `;
  
  document.body.appendChild(notification);
  
  // Auto-remove after 5 seconds
  setTimeout(() => {
    if (notification.parentNode) {
      notification.remove();
    }
  }, 5000);
};

// Playlist reordering functionality
function initializePlaylistReordering() {
  const playlistTable = document.getElementById('playlistSongsBody');
  
  if (playlistTable && playlistTable.querySelector('.drag-handle')) {
    console.log('Initializing playlist reordering');
    
    try {
      new Sortable(playlistTable, {
        animation: 150,
        handle: '.drag-handle',
        ghostClass: 'sortable-ghost',
        chosenClass: 'sortable-chosen',
        dragClass: 'sortable-drag',
        onStart: function(evt) {
          console.log('Drag started');
          // Show save/cancel buttons
          const saveBtn = document.getElementById('saveOrderBtn');
          const cancelBtn = document.getElementById('cancelOrderBtn');
          const reorderBtn = document.getElementById('reorderBtn');
          
          if (saveBtn) saveBtn.style.display = 'inline-block';
          if (cancelBtn) cancelBtn.style.display = 'inline-block';
          if (reorderBtn) reorderBtn.style.display = 'none';
        },
        onEnd: function(evt) {
          console.log('Drag ended');
          // The order has changed, but we don't save until user clicks "Save Order"
        }
      });
      
      console.log('SortableJS initialized successfully');
    } catch (error) {
      console.error('Error initializing SortableJS:', error);
    }
    
    // Save order button functionality
    const saveBtn = document.getElementById('saveOrderBtn');
    if (saveBtn) {
      console.log('Save button found, adding event listener');
      saveBtn.addEventListener('click', function(e) {
        console.log('Save button clicked!');
        e.preventDefault(); // Prevent any default form submission
        
        const songIds = Array.from(playlistTable.children).map(row => 
          row.dataset.songId
        );
        
        const playlistId = playlistTable.dataset.playlistId;
        console.log('Playlist ID:', playlistId);
        console.log('Saving new order:', songIds);
        
        if (!playlistId) {
          console.error('No playlist ID found!');
          alert('Error: Could not determine playlist ID');
          return;
        }
        
        // Use HTMX to send the new order
        const reorderUrl = `/playlists/${playlistId}/reorder`;
        console.log('Sending to URL:', reorderUrl);
        
        try {
          htmx.ajax('POST', reorderUrl, {
            target: '#playlistSongsBody',
            values: { song_ids: songIds },
            headers: {
              'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
            }
          });
          console.log('HTMX request sent successfully');
        } catch (error) {
          console.error('Error sending HTMX request:', error);
        }
        
        // Hide save/cancel buttons, show reorder button
        this.style.display = 'none';
        const cancelBtn = document.getElementById('cancelOrderBtn');
        const reorderBtn = document.getElementById('reorderBtn');
        if (cancelBtn) cancelBtn.style.display = 'none';
        if (reorderBtn) reorderBtn.style.display = 'inline-block';
      });
    } else {
      console.log('Save button not found');
    }
    
    // Cancel order button functionality
    const cancelBtn = document.getElementById('cancelOrderBtn');
    if (cancelBtn) {
      cancelBtn.addEventListener('click', function() {
        // Reload the page to reset the order
        window.location.reload();
      });
    }
  } else {
    console.log('Playlist table or drag handles not found');
  }
} 

// Playlist selection functionality
function initializePlaylistSelection() {
  console.log('Initializing playlist selection functionality');
  
  // Select all checkbox
  const selectAllCheckbox = document.getElementById('select-all-songs');
  if (selectAllCheckbox) {
    console.log('Select all checkbox found');
    selectAllCheckbox.addEventListener('change', function() {
      console.log('Select all checkbox changed');
      const songCheckboxes = document.querySelectorAll('.song-select-checkbox');
      songCheckboxes.forEach(checkbox => {
        checkbox.checked = this.checked;
      });
      updatePlaylistButtonState();
    });
  } else {
    console.log('Select all checkbox not found');
  }
  
  // Individual song checkboxes
  document.addEventListener('change', function(e) {
    if (e.target.classList.contains('song-select-checkbox')) {
      console.log('Individual song checkbox changed');
      updatePlaylistButtonState();
      updateSelectAllCheckbox();
    }
  });
  
  // Playlist dropdown options
  document.addEventListener('click', function(e) {
    console.log('Click event on:', e.target);
    console.log('Click event target classes:', e.target.className);
    console.log('Click event target id:', e.target.id);
    
    if (e.target.classList.contains('playlist-option')) {
      console.log('Playlist option clicked:', e.target.dataset);
      e.preventDefault();
      e.stopPropagation();
      const playlistId = e.target.dataset.playlistId;
      const playlistName = e.target.dataset.playlistName;
      addSelectedSongsToPlaylist(playlistId, playlistName);
    }
    
    if (e.target.id === 'createNewPlaylistOption') {
      console.log('Create new playlist option clicked');
      e.preventDefault();
      e.stopPropagation();
      showCreatePlaylistModal();
    }
  });
  
  // Also try direct event listeners on dropdown items
  setTimeout(() => {
    const playlistOptions = document.querySelectorAll('.playlist-option');
    console.log('Found playlist options:', playlistOptions.length);
    playlistOptions.forEach(option => {
      console.log('Adding direct listener to:', option.textContent);
      option.addEventListener('click', function(e) {
        console.log('Direct playlist option click:', this.dataset);
        e.preventDefault();
        e.stopPropagation();
        const playlistId = this.dataset.playlistId;
        const playlistName = this.dataset.playlistName;
        addSelectedSongsToPlaylist(playlistId, playlistName);
      });
    });
    
    const createOption = document.getElementById('createNewPlaylistOption');
    if (createOption) {
      console.log('Adding direct listener to create option');
      createOption.addEventListener('click', function(e) {
        console.log('Direct create option click');
        e.preventDefault();
        e.stopPropagation();
        showCreatePlaylistModal();
      });
    }
  }, 100);
  
  // Initialize button state
  updatePlaylistButtonState();
}

function updatePlaylistButtonState() {
  const selectedSongs = document.querySelectorAll('.song-select-checkbox:checked');
  const dropdownButton = document.getElementById('addToPlaylistDropdown');
  
  if (dropdownButton) {
    if (selectedSongs.length > 0) {
      dropdownButton.disabled = false;
      dropdownButton.textContent = `Add to Playlist (${selectedSongs.length})`;
    } else {
      dropdownButton.disabled = true;
      dropdownButton.innerHTML = '<i class="fas fa-plus me-1"></i>Add to Playlist';
    }
  }
}

function updateSelectAllCheckbox() {
  const selectAllCheckbox = document.getElementById('select-all-songs');
  const songCheckboxes = document.querySelectorAll('.song-select-checkbox');
  const checkedCheckboxes = document.querySelectorAll('.song-select-checkbox:checked');
  
  if (selectAllCheckbox) {
    if (checkedCheckboxes.length === 0) {
      selectAllCheckbox.checked = false;
      selectAllCheckbox.indeterminate = false;
    } else if (checkedCheckboxes.length === songCheckboxes.length) {
      selectAllCheckbox.checked = true;
      selectAllCheckbox.indeterminate = false;
    } else {
      selectAllCheckbox.checked = false;
      selectAllCheckbox.indeterminate = true;
    }
  }
}

// Playlist song removal functionality
function initializePlaylistSongRemoval() {
  // Select all checkbox for playlist songs
  const selectAllPlaylistCheckbox = document.getElementById('select-all-playlist-songs');
  if (selectAllPlaylistCheckbox) {
    selectAllPlaylistCheckbox.addEventListener('change', function() {
      const songCheckboxes = document.querySelectorAll('.playlist-song-select-checkbox');
      songCheckboxes.forEach(checkbox => {
        checkbox.checked = this.checked;
      });
      updatePlaylistRemoveButtonState();
    });
  }
  
  // Individual playlist song checkboxes
  document.addEventListener('change', function(e) {
    if (e.target.classList.contains('playlist-song-select-checkbox')) {
      updatePlaylistRemoveButtonState();
      updateSelectAllPlaylistCheckbox();
    }
  });
  
  // Remove from playlist button
  const removeBtn = document.getElementById('removeFromPlaylistBtn');
  if (removeBtn) {
    removeBtn.addEventListener('click', function() {
      removeSelectedSongsFromPlaylist();
    });
  }
}

function updatePlaylistRemoveButtonState() {
  const selectedSongs = document.querySelectorAll('.playlist-song-select-checkbox:checked');
  const removeButton = document.getElementById('removeFromPlaylistBtn');
  
  if (removeButton) {
    if (selectedSongs.length > 0) {
      removeButton.style.display = 'inline-block';
      removeButton.textContent = `Remove Selected (${selectedSongs.length})`;
    } else {
      removeButton.style.display = 'none';
    }
  }
}

function updateSelectAllPlaylistCheckbox() {
  const selectAllCheckbox = document.getElementById('select-all-playlist-songs');
  const songCheckboxes = document.querySelectorAll('.playlist-song-select-checkbox');
  const checkedCheckboxes = document.querySelectorAll('.playlist-song-select-checkbox:checked');
  
  if (selectAllCheckbox) {
    if (checkedCheckboxes.length === 0) {
      selectAllCheckbox.checked = false;
      selectAllCheckbox.indeterminate = false;
    } else if (checkedCheckboxes.length === songCheckboxes.length) {
      selectAllCheckbox.checked = true;
      selectAllCheckbox.indeterminate = false;
    } else {
      selectAllCheckbox.checked = false;
      selectAllCheckbox.indeterminate = true;
    }
  }
}

function removeSelectedSongsFromPlaylist() {
  const selectedSongs = document.querySelectorAll('.playlist-song-select-checkbox:checked');
  const songIds = Array.from(selectedSongs).map(checkbox => checkbox.value);
  const playlistId = document.getElementById('playlistSongsBody').dataset.playlistId;
  
  if (songIds.length === 0) {
    alert('Please select at least one song to remove from the playlist.');
    return;
  }
  
  if (confirm(`Are you sure you want to remove ${songIds.length} song(s) from this playlist?`)) {
    console.log(`Removing ${songIds.length} songs from playlist: ${playlistId}`);
    
    // Use HTMX to remove songs from playlist
    htmx.ajax('DELETE', `/playlists/${playlistId}/remove_songs`, {
      target: '#playlistSongsBody',
      values: { song_ids: songIds },
      headers: {
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
      }
    });
    
    // Clear selections
    selectedSongs.forEach(checkbox => checkbox.checked = false);
    updatePlaylistRemoveButtonState();
    updateSelectAllPlaylistCheckbox();
  }
} 

// Custom JavaScript for the music archive
document.addEventListener('turbo:load', function() {
  // Initialize any custom JavaScript here
  console.log('Music Archive loaded');
  
  // Ensure global functions are available
  console.log('Global functions check:');
  console.log('addSelectedSongsToPlaylist:', typeof window.addSelectedSongsToPlaylist);
  console.log('showCreatePlaylistModal:', typeof window.showCreatePlaylistModal);
  
  // Initialize playlist reordering
  initializePlaylistReordering();
  
  // Initialize playlist selection functionality
  initializePlaylistSelection();
  
  // Initialize playlist song removal functionality
  initializePlaylistSongRemoval();
});

// Also ensure functions are available on DOMContentLoaded
document.addEventListener('DOMContentLoaded', function() {
  console.log('DOMContentLoaded - Global functions check:');
  console.log('addSelectedSongsToPlaylist:', typeof window.addSelectedSongsToPlaylist);
  console.log('showCreatePlaylistModal:', typeof window.showCreatePlaylistModal);
}); 