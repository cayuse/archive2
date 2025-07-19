# PowerSync Configuration for Music Archive
# This enables real-time synchronization of music metadata to jukebox systems
# Note: PowerSync is implemented as a custom service, not as a Rails gem

# PowerSync.configure do |config|
#   # Enable PowerSync for this Rails application
#   config.enabled = true
#   
#   # Configure the database schema for synchronization
#   config.schema = {
#     # Core music metadata tables
#     songs: {
#       id: :integer,
#       title: :string,
#       artist: :string,
#       album: :string,
#       genre: :string,
#       year: :integer,
#       duration: :integer,
#       file_path: :string,
#       file_size: :integer,
#       bitrate: :integer,
#       sample_rate: :integer,
#       channels: :integer,
#       created_at: :datetime,
#       updated_at: :datetime
#     },
#     
#     artists: {
#       id: :integer,
#       name: :string,
#       bio: :text,
#       created_at: :datetime,
#       updated_at: :datetime
#     },
#     
#     albums: {
#       id: :integer,
#       title: :string,
#       artist_id: :integer,
#       year: :integer,
#       genre: :string,
#       cover_art_path: :string,
#       created_at: :datetime,
#       updated_at: :datetime
#     },
#     
#     genres: {
#       id: :integer,
#       name: :string,
#       description: :text,
#       created_at: :datetime,
#       updated_at: :datetime
#     },
#     
#     playlists: {
#       id: :integer,
#       name: :string,
#       description: :text,
#       user_id: :integer,
#       is_public: :boolean,
#       created_at: :datetime,
#       updated_at: :datetime
#     },
#     
#     playlist_songs: {
#       id: :integer,
#       playlist_id: :integer,
#       song_id: :integer,
#       position: :integer,
#       created_at: :datetime,
#       updated_at: :datetime
#     },
#     
#     users: {
#       id: :integer,
#       name: :string,
#       email: :string,
#       role: :string,
#       created_at: :datetime,
#       updated_at: :datetime
#     }
#   }
#   
#   # Configure access control for jukebox systems
#   config.access_control = {
#     # Jukebox systems can read all music metadata
#     jukebox: {
#       read: [:songs, :artists, :albums, :genres, :playlists, :playlist_songs, :users],
#       users],
#       write: [] # Jukeboxes don't write back to archive
#     }
#   }
#   
#   # Configure sync intervals and settings
#   config.sync_settings = {
#     # Sync every 30 seconds by default
#     interval: 30,
#     
#     # Maximum batch size for sync operations
#     batch_size: 1000,
#     
#     # Enable conflict resolution
#     conflict_resolution: :server_wins,
#     
#     # Log sync operations in development
#     logging: Rails.env.development?
#   }
# end 