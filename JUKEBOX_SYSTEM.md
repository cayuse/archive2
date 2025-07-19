# Jukebox System Documentation

## 🎵 Overview

The Jukebox System is a rock-solid, automated music player that combines the reliability of MPD (Music Player Daemon) with intelligent queue management and caching. It provides continuous music playback with user-requested songs taking priority over random selections.

## 🏗️ Architecture

### Core Components

1. **Rails Backend** (`jukebox/`) - Web interface and queue management
2. **Python Audio Player** (`jukebox/audio_player/`) - MPD controller with Redis communication
3. **MPD (Music Player Daemon)** - Battle-tested audio playback engine
4. **Redis** - Real-time queue management and caching
5. **File Cache System** - Local song storage for reliable playback

### System Flow

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Rails App     │    │   Python        │    │   MPD           │
│   (jukebox)     │◄──►│   Controller    │◄──►│   (Audio       │
│                 │    │                 │    │    Engine)      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Redis         │    │   File Cache    │    │   Audio Output  │
│   (Queues)      │    │   (Songs)       │    │   (Speakers)    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 🚀 Quick Setup

### Automated Setup (Recommended)

```bash
# Run the automated setup script
chmod +x jukebox_setup.sh
./jukebox_setup.sh
```

### Manual Setup

1. **Install Dependencies**
   ```bash
   sudo apt install mpd mpc redis-server python3 python3-pip ffmpeg
   ```

2. **Configure MPD**
   ```bash
   sudo cp /etc/mpd.conf /etc/mpd.conf.backup
   # Edit /etc/mpd.conf for jukebox settings
   ```

3. **Set up Python Environment**
   ```bash
   cd jukebox/audio_player
   python3 -m venv venv
   source venv/bin/activate
   pip install -r requirements.txt
   ```

4. **Configure Rails**
   ```bash
   cd jukebox
   bin/rails db:create
   bin/rails db:migrate
   ```

## 📋 Features

### Queue Management
- **User Queue**: FIFO queue for user-requested songs (takes priority)
- **Random Pool**: Shuffled songs from selected playlists
- **Automatic Refill**: Random pool refills when low
- **Empty State Handling**: Graceful handling when no content is available
- **Follow-up Songs**: Future feature for songs that should play together

### Audio Playback
- **Rock-solid**: Uses MPD daemon for reliable playback
- **Crossfade**: Configurable crossfade between songs
- **Volume Control**: System-wide volume management
- **Multiple Formats**: Supports MP3, WAV, FLAC, etc.
- **Smart Pausing**: Automatically pauses when no content available
- **User Control**: Requires manual resume when content is added

### Caching System
- **Automatic Download**: Songs cached before playback
- **Persistent Storage**: Cached songs remain available
- **Background Processing**: Non-blocking downloads
- **Error Recovery**: Retry failed downloads

### Control Interface
- **Web Interface**: Rails-based control panel
- **Redis Commands**: Real-time control via Redis
- **MPD Commands**: Direct MPD control via `mpc`
- **Systemd Service**: Managed as system service

## 🎛️ Configuration

### Player Configuration (`jukebox/audio_player/config.json`)

```json
{
    "mpd_host": "localhost",
    "mpd_port": 6600,
    "mpd_password": null,
    "redis_host": "localhost",
    "redis_port": 6379,
    "redis_db": 0,
    "jukebox_api_url": "http://localhost:3001/api",
    "cache_directory": "/var/lib/jukebox/cache",
    "crossfade_duration": 3,
    "volume": 80,
    "retry_attempts": 3,
    "retry_delay": 5
}
```

### MPD Configuration (`/etc/mpd.conf`)

Key settings for jukebox:
```ini
music_directory         "/var/lib/jukebox/cache"
crossfade_time         "3"
audio_buffer_size      "8192"
buffer_before_play     "25%"
```

## 🎮 Usage

### Starting the System

```bash
# Start all services
sudo systemctl start mpd redis-server jukebox-player

# Check status
sudo systemctl status jukebox-player

# View logs
sudo journalctl -u jukebox-player -f
```

### Web Interface

1. **Start Rails Server**
   ```bash
   cd jukebox
   bin/rails server -p 3001
   ```

2. **Access Interface**
   - URL: http://localhost:3001
   - Browse songs and add to queue
   - View current playback status
   - Manage playlists

### Command Line Control

```bash
# MPD Control
mpc play          # Start playback
mpc pause         # Pause playback
mpc next          # Next song
mpc prev          # Previous song
mpc volume 80     # Set volume

# Redis Queue Management
redis-cli llen jukebox:queue           # Queue length
redis-cli lrange jukebox:queue 0 -1    # View queue
redis-cli get jukebox:current_song     # Current song
```

### API Endpoints

```bash
# Get system status
GET /api/jukebox/status

# Get system health and recommendations
GET /api/jukebox/health

# Add song to queue
POST /api/jukebox/queue
{
    "song_id": 123
}

# Get current queue
GET /api/jukebox/queue

# Remove song from queue
DELETE /api/jukebox/queue/0

# Clear entire queue
DELETE /api/jukebox/queue

# Control playback
POST /api/jukebox/control
{
    "action": "play|pause|stop|next|previous|volume|crossfade|refill",
    "volume": 80,
    "duration": 3
}

# Get cached songs
GET /api/jukebox/cached_songs
```

## 🔧 Database Schema

### Core Models

#### Playlist
- `name` - Playlist name
- `archive_playlist_id` - Reference to archive playlist
- `jukebox_enabled` - Enable for jukebox
- `crossfade_duration` - Crossfade setting
- `volume` - Volume setting

#### QueueItem
- `song_id` - Reference to archive song
- `user_id` - User who requested
- `position` - Queue position
- `status` - pending/playing/played/skipped

#### CachedSong
- `song_id` - Reference to archive song
- `file_path` - Local file path
- `file_size` - File size in bytes
- `status` - downloading/completed/failed

## 🛠️ Troubleshooting

### Empty State Handling

The jukebox system gracefully handles scenarios where no content is available:

#### **No Playlists Enabled**
- **State**: `no_playlists`
- **Message**: "No playlists are enabled for jukebox playback"
- **Solution**: Enable at least one playlist for jukebox in the admin interface

#### **No Songs in Playlists**
- **State**: `no_songs`
- **Message**: "No songs found in enabled playlists"
- **Solution**: Add songs to playlists or enable playlists with content

#### **Empty Queues**
- **State**: `paused`
- **Message**: "No songs available in queue or random pool"
- **Solution**: Add songs to queue or ensure playlists are populated

#### **System Behavior**
- Player automatically pauses when no content is available
- No automatic retry - waits for user interaction
- Checks every 10 seconds for new content
- Clear status messages indicate what needs to be configured
- User must manually resume playback when content is added

### Common Issues

1. **MPD Connection Failed**
   ```bash
   # Check MPD status
   sudo systemctl status mpd
   
   # Check MPD logs
   sudo journalctl -u mpd -f
   
   # Test connection
   mpc status
   ```

2. **Redis Connection Failed**
   ```bash
   # Check Redis status
   sudo systemctl status redis-server
   
   # Test connection
   redis-cli ping
   ```

3. **Audio Not Playing**
   ```bash
   # Check audio devices
   aplay -l
   
   # Test audio
   speaker-test -t wav -c 2
   
   # Check MPD audio output
   mpc outputs
   ```

4. **Songs Not Downloading**
   ```bash
   # Check cache directory
   ls -la /var/lib/jukebox/cache
   
   # Check download job logs
   tail -f jukebox/log/development.log
   
   # Test API connection
   curl http://localhost:3000/api/songs/1/download
   ```

### Debug Commands

```bash
# Player status
sudo systemctl status jukebox-player

# MPD status
mpc status

# Redis queues
redis-cli keys "jukebox:*"

# System status
redis-cli get jukebox:status

# Queue status
redis-cli llen jukebox:queue
redis-cli llen jukebox:random_pool

# Cache status
ls -la /var/lib/jukebox/cache | wc -l

# Log monitoring
sudo journalctl -u jukebox-player -f &
tail -f jukebox/log/development.log &

# API health check
curl http://localhost:3001/api/jukebox/health
```

## 🔄 Maintenance

### Regular Tasks

1. **Cache Cleanup**
   ```bash
   # Remove old cached files (older than 30 days)
   find /var/lib/jukebox/cache -type f -mtime +30 -delete
   ```

2. **Database Cleanup**
   ```bash
   # Clean old queue items
   cd jukebox
   bin/rails runner "QueueItem.where('created_at < ?', 7.days.ago).delete_all"
   ```

3. **Log Rotation**
   ```bash
   # Configure logrotate for jukebox logs
   sudo tee /etc/logrotate.d/jukebox > /dev/null << 'EOF'
   /var/lib/jukebox/logs/*.log {
       daily
       missingok
       rotate 7
       compress
       delaycompress
       notifempty
       create 644 vscode vscode
   }
   EOF
   ```

### Performance Monitoring

```bash
# Monitor system resources
htop

# Monitor disk usage
df -h /var/lib/jukebox/cache

# Monitor Redis memory
redis-cli info memory

# Monitor MPD status
mpc stats
```

## 🔮 Future Enhancements

### Planned Features

1. **Follow-up Songs**
   - Automatic pairing of related songs
   - Configurable rules for song sequences

2. **Smart Playlists**
   - Dynamic playlist generation
   - Mood-based song selection
   - Time-based playlist rules

3. **Multi-room Audio**
   - Multiple MPD instances
   - Synchronized playback
   - Zone-based control

4. **Advanced Analytics**
   - Playback statistics
   - User preference learning
   - Popular song tracking

5. **Mobile App**
   - Native mobile interface
   - Remote queue management
   - Push notifications

### Integration Possibilities

- **Spotify Integration**: Import playlists from Spotify
- **Last.fm Scrobbling**: Track listening history
- **Voice Control**: Alexa/Google Home integration
- **Web Radio**: Internet radio station support
- **Podcast Support**: Podcast episode playback

## 📚 Additional Resources

- [MPD Documentation](https://mpd.readthedocs.io/)
- [Redis Documentation](https://redis.io/documentation)
- [Python MPD2 Library](https://python-mpd2.readthedocs.io/)
- [Rails Active Job](https://guides.rubyonrails.org/active_job_basics.html)

## 🆘 Support

For issues or questions:
1. Check the troubleshooting section above
2. Review system logs for error messages
3. Verify all services are running
4. Test individual components (MPD, Redis, Rails)
5. Check configuration files for syntax errors 