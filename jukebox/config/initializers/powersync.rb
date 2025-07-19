# PowerSync Client Configuration for Jukebox
# This enables the jukebox to sync music metadata from the archive
# Note: PowerSync is implemented as a custom service, not as a Rails gem

# PowerSync::Client.configure do |config|
#   # Archive server URL
#   config.server_url = ENV.fetch('ARCHIVE_SERVER_URL', 'http://localhost:3000')
#   
#   # PowerSync endpoint on the archive
#   config.sync_endpoint = '/powersync'
#   
#   # Jukebox client identifier
#   config.client_id = ENV.fetch('JUKEBOX_CLIENT_ID', 'jukebox-1')
#   
#   # Sync configuration
#   config.sync_settings = {
#     # Sync every 30 seconds
#     interval: 30,
#     
#     # Maximum batch size for sync operations
#     batch_size: 1000,
#     
#     # Retry settings
#     retry_attempts: 3,
#     retry_delay: 5,
#     
#     # Conflict resolution (client wins for jukebox-specific data)
#     conflict_resolution: :client_wins,
#     
#     # Log sync operations in development
#     logging: Rails.env.development?
#   }
#   
#   # Tables to sync from archive
#   config.sync_tables = [
#     :songs,
#     :artists, 
#     :albums,
#     :genres,
#     :playlists,
#     :playlist_songs,
#     :users
#   ]
#   
#   # Local tables (jukebox-specific, not synced)
#   config.local_tables = [
#     :queue_items,
#     :cached_songs,
#     :jukebox_settings
#   ]
#   
#   # Authentication for sync (if needed)
#   config.authentication = {
#     type: :api_key,
#     api_key: ENV.fetch('ARCHIVE_API_KEY', nil)
#   }
# end 