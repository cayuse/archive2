# PowerSync Jukebox System Documentation

## 🎵 Overview

The PowerSync Jukebox System is a distributed music playback solution that separates the music archive from jukebox players using PowerSync for real-time data synchronization. This architecture allows jukeboxes to operate independently while maintaining access to the complete music library metadata.

## 🏗️ Architecture

### System Components

```
┌─────────────────┐    PowerSync    ┌─────────────────┐
│   Archive       │◄──────────────►│   Jukebox       │
│   Server        │   (Metadata)    │   Player        │
│                 │                 │                 │
│ ┌─────────────┐ │                 │ ┌─────────────┐ │
│ │ PostgreSQL  │ │                 │ │ SQLite      │ │
│ │ Database    │ │                 │ │ Database    │ │
│ └─────────────┘ │                 │ └─────────────┘ │
│                 │                 │                 │
│ ┌─────────────┐ │                 │ ┌─────────────┐ │
│ │ PowerSync   │ │                 │ │ PowerSync   │ │
│ │ Server      │ │                 │ │ Client      │ │
│ └─────────────┘ │                 │ └─────────────┘ │
└─────────────────┘                 └─────────────────┘
         │                                   │
         │                                   │
         ▼                                   ▼
┌─────────────────┐                 ┌─────────────────┐
│   Music Files   │                 │   Audio Player  │
│   (Storage)     │                 │   (MPD + Redis) │
└─────────────────┘                 └─────────────────┘
```

### Data Flow

1. **Archive Server**: Central repository for music metadata and files
2. **PowerSync**: Real-time synchronization of metadata (songs, artists, albums, playlists)
3. **Jukebox**: Local SQLite database with synced metadata + local cache for audio files
4. **Audio Player**: MPD-based playback with Redis queue management

## 🚀 Quick Setup

### Automated Setup (Recommended)

```bash
# Run the complete PowerSync setup script
chmod +x jukebox_powersync_setup.sh
./jukebox_powersync_setup.sh
```

### Manual Setup

1. **Archive Server Setup**
   ```bash
   cd archive
   bundle install
   docker-compose up -d
   ```

2. **Jukebox Setup**
   ```bash
   cd jukebox
   bundle install
   bin/rails db:create
   bin/rails db:migrate
   bin/rails server -p 3001
   ```

3. **Audio System Setup**
   ```bash
   sudo apt install mpd mpc redis-server python3
   sudo systemctl start mpd redis-server
   cd jukebox/audio_player
   python3 -m venv venv
   source venv/bin/activate
   pip install -r requirements.txt
   ```

## 📋 Features

### PowerSync Synchronization
- **Real-time Sync**: Metadata updates propagate automatically
- **Offline Capability**: Jukebox works with cached data when offline
- **Conflict Resolution**: Server-wins for metadata, client-wins for local data
- **Selective Sync**: Only metadata syncs, audio files download on-demand

### Jukebox Functionality
- **Fast Search**: Local SQLite database enables instant searches
- **Queue Management**: User-requested songs with FIFO priority
- **Random Play**: Shuffled songs from public playlists
- **Smart Caching**: Audio files downloaded when queued
- **Crossfade**: Smooth transitions between songs

### Archive Integration
- **Metadata Access**: Full access to songs, artists, albums, genres, playlists
- **File Downloads**: On-demand audio file caching
- **API Access**: RESTful API for remote control
- **User Management**: Synced user accounts and permissions

## 🎛️ Configuration

### Archive Server Configuration

**PowerSync Initializer** (`archive/config/initializers/powersync.rb`):
```ruby
PowerSync.configure do |config|
  config.enabled = true
  config.schema = {
    songs: { /* schema definition */ },
    artists: { /* schema definition */ },
    # ... other tables
  }
  config.access_control = {
    jukebox: {
      read: [:songs, :artists, :albums, :genres, :playlists, :playlist_songs, :users],
      write: []
    }
  }
end
```

### Jukebox Configuration

**Environment Variables** (`jukebox/.env`):
```bash
# Archive Server Configuration
ARCHIVE_SERVER_URL=http://localhost:3000
ARCHIVE_API_KEY=

# Jukebox Client Configuration
JUKEBOX_CLIENT_ID=jukebox-1

# Redis Configuration
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_DB=0

# PowerSync Configuration
POWERSYNC_ENABLED=true
POWERSYNC_SYNC_INTERVAL=30
```

**PowerSync Client** (`jukebox/config/initializers/powersync.rb`):
```ruby
PowerSync::Client.configure do |config|
  config.server_url = ENV.fetch('ARCHIVE_SERVER_URL', 'http://localhost:3000')
  config.sync_tables = [:songs, :artists, :albums, :genres, :playlists, :playlist_songs, :users]
  config.local_tables = [:queue_items, :cached_songs, :jukebox_settings]
end
```

## 🎮 Usage

### Starting the System

```bash
# 1. Start Archive Server
cd archive
docker-compose up -d

# 2. Start Jukebox Rails Server
cd jukebox
bin/rails server -p 3001

# 3. Start Audio Player
sudo systemctl start jukebox-player

# 4. Check Status
curl http://localhost:3001/api/jukebox/health
```

### Web Interface

- **Jukebox Dashboard**: http://localhost:3001
- **Search Interface**: http://localhost:3001/search
- **Queue Management**: http://localhost:3001/queue
- **Cache Status**: http://localhost:3001/cache
- **Sync Status**: http://localhost:3001/sync

### API Endpoints

#### System Status
```bash
# Get system status
GET /api/jukebox/status

# Get system health
GET /api/jukebox/health

# Get sync status
GET /api/jukebox/sync

# Force sync
POST /api/jukebox/sync/force
```

#### Queue Management
```bash
# Get current queue
GET /api/jukebox/queue

# Add song to queue
POST /api/jukebox/queue
{
    "song_id": 123
}

# Remove song from queue
DELETE /api/jukebox/queue/0

# Clear queue
DELETE /api/jukebox/queue
```

#### Player Control
```bash
# Play
POST /api/jukebox/player/play

# Pause
POST /api/jukebox/player/pause

# Skip
POST /api/jukebox/player/skip

# Set volume
POST /api/jukebox/player/volume
{
    "volume": 80
}
```

#### Search and Browse
```bash
# Search songs
GET /api/jukebox/search/songs?q=query

# Search artists
GET /api/jukebox/search/artists?q=query

# Get songs by artist
GET /api/jukebox/songs/by_artist/Artist%20Name

# Get popular playlists
GET /api/jukebox/playlists/popular
```

#### Cache Management
```bash
# Get cache status
GET /api/jukebox/cache/status

# Cache specific song
POST /api/jukebox/cache/song/123

# Clear cache
DELETE /api/jukebox/cache
```

## 🔧 Troubleshooting

### Common Issues

1. **Sync Not Working**
   ```bash
   # Check sync status
   curl http://localhost:3001/api/jukebox/sync
   
   # Force sync
   curl -X POST http://localhost:3001/api/jukebox/sync/force
   
   # Check archive connectivity
   curl http://localhost:3000/up
   ```

2. **No Songs Available**
   ```bash
   # Check if songs are synced
   curl http://localhost:3001/api/jukebox/status
   
   # Check archive has songs
   curl http://localhost:3000/api/v1/songs
   ```

3. **Audio Player Issues**
   ```bash
   # Check MPD status
   mpc status
   
   # Check Redis connection
   redis-cli ping
   
   # Check player service
   sudo systemctl status jukebox-player
   ```

4. **Database Issues**
   ```bash
   # Reset jukebox database
   cd jukebox
   bin/rails db:reset
   
   # Check SQLite database
   bin/rails dbconsole
   ```

### Logs and Monitoring

```bash
# Jukebox Rails logs
tail -f jukebox/log/development.log

# Audio player logs
sudo journalctl -u jukebox-player -f

# MPD logs
sudo tail -f /var/log/mpd/mpd.log

# Redis logs
sudo tail -f /var/log/redis/redis-server.log
```

## 🔮 Advanced Features

### Multiple Jukeboxes

The system supports multiple jukeboxes connecting to the same archive:

```bash
# Configure different client IDs
JUKEBOX_CLIENT_ID=jukebox-1  # First jukebox
JUKEBOX_CLIENT_ID=jukebox-2  # Second jukebox
```

### Custom Sync Intervals

```ruby
# In jukebox/config/initializers/powersync.rb
config.sync_settings = {
  interval: 60,  # Sync every minute
  batch_size: 500,
  retry_attempts: 5
}
```

### Selective Table Sync

```ruby
# Only sync specific tables
config.sync_tables = [:songs, :playlists]  # Skip artists, albums, etc.
```

### Offline Mode

The jukebox can operate offline with cached data:
- Metadata remains available for search
- Cached songs can be played
- Queue management continues to work
- Sync resumes when connection is restored

## 📚 API Reference

### Song Object
```json
{
  "id": 123,
  "title": "Song Title",
  "artist": "Artist Name",
  "album": "Album Title",
  "genre": "Genre",
  "year": 2020,
  "duration": 180,
  "file_path": "/path/to/song.mp3",
  "file_size": 5242880,
  "bitrate": 320,
  "sample_rate": 44100,
  "channels": 2,
  "cached": true,
  "created_at": "2024-01-01T00:00:00Z",
  "updated_at": "2024-01-01T00:00:00Z"
}
```

### Queue Item Object
```json
{
  "id": 456,
  "song_id": 123,
  "position": 0,
  "added_at": "2024-01-01T00:00:00Z",
  "song": {
    "id": 123,
    "title": "Song Title",
    "artist": "Artist Name"
  }
}
```

### System Status Object
```json
{
  "current_song": {
    "id": 123,
    "title": "Song Title",
    "artist": "Artist Name",
    "album": "Album Title",
    "duration": 180,
    "cached": true
  },
  "queue_length": 5,
  "random_pool_size": 20,
  "is_playing": true,
  "volume": 80,
  "cached_songs_count": 150,
  "synced_songs_count": 1000,
  "last_sync": "2024-01-01T00:00:00Z"
}
```

## 🆘 Support

For issues or questions:

1. **Check System Health**: `curl http://localhost:3001/api/jukebox/health`
2. **Review Logs**: Check Rails, MPD, and Redis logs
3. **Verify Services**: Ensure all services are running
4. **Test Connectivity**: Check archive and Redis connections
5. **Reset if Needed**: Use setup scripts to reset the system

## 📖 Additional Resources

- [PowerSync Documentation](https://powersync.co/docs)
- [MPD Documentation](https://mpd.readthedocs.io/)
- [Redis Documentation](https://redis.io/documentation)
- [Rails Active Job](https://guides.rubyonrails.org/active_job_basics.html)
- [SQLite Documentation](https://www.sqlite.org/docs.html) 