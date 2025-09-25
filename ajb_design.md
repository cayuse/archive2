# Archive Jukebox (AJB) - Design Document

## Project Overview

Archive Jukebox (AJB) is a multi-tenant music streaming system that extends the existing Archive music collection with party-based jukebox capabilities. The system consists of two main interfaces:

1. **Archive.cavaforge.net** - Admin interface for authenticated users to create and manage party sessions
2. **Jukebox.cavaforge.net** - Guest interface for party attendees to request songs and view queues

## Architecture Overview

### Two-Phase System Design

**Phase 1: Party Creation & Management (Archive.cavaforge.net)**
- Authenticated users create party sessions with unique session IDs
- Deploy JavaScript-based music player applications
- Manage party settings (start/stop times, session names, passwords)
- Monitor active parties and playback statistics

**Phase 2: Party Participation (Jukebox.cavaforge.net)**
- Guests enter session ID/password or scan QR codes
- Search and request songs for the party queue
- View current queue and now playing information
- Real-time updates of party status

### Owner's Player Application

The core component is a JavaScript Single Page Application (SPA) that:
- Runs entirely in the browser (iPad, phone, computer)
- Actually plays music from Archive's API
- Has admin controls (skip, remove songs, bump to top)
- Reports playback status back to Archive
- Connects to speakers via the device
- Handles complete file downloads for high-quality playback

## Technology Stack

### Frontend Framework: React.js

**Rationale:**
- Component-based architecture perfect for music player UI
- Strong ecosystem with audio-specific libraries
- Real-time updates via hooks and state management
- Cross-platform compatibility across target devices
- Excellent developer experience and tooling
- Bundle size (~45KB gzipped) acceptable for use case

### Audio Engine: Howler.js + Web Audio API + Tone.js

**Primary Audio Strategy:**
- **Howler.js** - Cross-platform audio abstraction layer
- **Web Audio API** - Advanced audio processing and crossfading
- **Tone.js** - High-level audio framework for complex effects
- **No fallbacks** - Modern browsers only approach

**Advanced Audio Features:**
- **Crossfading** between songs (2-8 second customizable fade)
- **Real-time audio mixing** with overlapping playback
- **Gain control** for smooth volume transitions
- **Audio context management** for seamless transitions

**Audio Quality Requirements:**
- Full song file downloads (not streaming)
- Complete file cache before playback begins
- No adaptive bitrate - full quality always
- Pre-download next song 5-10 seconds before current ends

**File Download Strategy:**
- Complete song files (~15MB average)
- Download time at 100Mbps: ~1.2 seconds
- Pre-download with 5-10 second buffer
- Local cache using modern web storage APIs
- No playback until fully downloaded

## Advanced Audio Features: Crossfading

### Crossfade Implementation Strategy

**Technology Stack for Crossfading:**
- **Web Audio API** - Low-level audio control for precise timing
- **Tone.js CrossFade Node** - Simplified crossfade implementation
- **AudioBufferSourceNode** - Individual track control
- **GainNode** - Volume control for smooth transitions

### Crossfade Technical Implementation

**Basic Crossfade with Web Audio API:**
```javascript
class CrossfadePlayer {
  constructor() {
    this.audioContext = new AudioContext();
    this.currentTrack = null;
    this.nextTrack = null;
    this.crossfadeDuration = 3000; // 3 seconds default
  }

  async loadAudioBuffer(url) {
    const response = await fetch(url);
    const arrayBuffer = await response.arrayBuffer();
    return await this.audioContext.decodeAudioData(arrayBuffer);
  }

  createAudioSource(buffer) {
    const source = this.audioContext.createBufferSource();
    const gainNode = this.audioContext.createGain();
    
    source.buffer = buffer;
    source.connect(gainNode);
    gainNode.connect(this.audioContext.destination);
    
    return { source, gainNode };
  }

  async crossfadeToNext(nextSongUrl) {
    const now = this.audioContext.currentTime;
    
    // Load next track
    const nextBuffer = await this.loadAudioBuffer(nextSongUrl);
    const nextAudio = this.createAudioSource(nextBuffer);
    
    // Start next track at low volume
    nextAudio.source.start(now);
    nextAudio.gainNode.gain.setValueAtTime(0, now);
    nextAudio.gainNode.gain.linearRampToValueAtTime(1, now + this.crossfadeDuration);
    
    // Fade out current track
    if (this.currentTrack) {
      this.currentTrack.gainNode.gain.setValueAtTime(1, now);
      this.currentTrack.gainNode.gain.linearRampToValueAtTime(0, now + this.crossfadeDuration);
      this.currentTrack.source.stop(now + this.crossfadeDuration);
    }
    
    // Update current track reference
    this.currentTrack = nextAudio;
  }
}
```

**Enhanced Crossfade with Tone.js:**
```javascript
import * as Tone from 'tone';

class AdvancedCrossfadePlayer {
  constructor() {
    this.crossfade = new Tone.CrossFade(0.5); // 50% mix initially
    this.player1 = new Tone.Player().connect(this.crossfade.a);
    this.player2 = new Tone.Player().connect(this.crossfade.b);
    this.crossfade.connect(Tone.Destination);
    
    this.currentPlayer = this.player1;
    this.nextPlayer = this.player2;
  }

  async crossfadeToNext(songUrl, fadeDuration = 3) {
    // Load next song into next player
    await this.nextPlayer.load(songUrl);
    
    // Start next player
    this.nextPlayer.start();
    
    // Crossfade over specified duration
    this.crossfade.fade.value = 0;
    this.crossfade.fade.rampTo(1, fadeDuration);
    
    // Switch player references for next crossfade
    [this.currentPlayer, this.nextPlayer] = [this.nextPlayer, this.currentPlayer];
  }
}
```

### Crossfade Configuration Options

**Customizable Crossfade Settings:**
```javascript
const crossfadeConfig = {
  enabled: true,
  duration: 3000, // 3 seconds default
  curve: 'linear', // linear, exponential, logarithmic
  autoCrossfade: true, // Auto-crossfade on song end
  manualCrossfade: true, // Allow manual crossfade triggers
  crossfadeTypes: {
    'smooth': 3000,    // 3 second smooth fade
    'quick': 1000,     // 1 second quick fade
    'long': 8000,      // 8 second long fade
    'beat-match': 4000 // 4 second beat-matched fade
  }
};
```

**Smart Crossfade Timing:**
```javascript
const smartCrossfadeTiming = (currentSong, nextSong) => {
  const currentDuration = currentSong.duration;
  const nextDuration = nextSong.duration;
  
  // Start crossfade 5-10 seconds before end of current song
  const crossfadeStart = Math.max(currentDuration - 5000, 0);
  
  // Adjust crossfade duration based on song characteristics
  let crossfadeDuration = 3000; // default
  
  if (currentSong.genre === 'electronic' && nextSong.genre === 'electronic') {
    crossfadeDuration = 4000; // Longer for electronic music
  } else if (currentSong.genre === 'classical' || nextSong.genre === 'classical') {
    crossfadeDuration = 2000; // Shorter for classical
  }
  
  return { crossfadeStart, crossfadeDuration };
};
```

### Crossfade User Interface

**Owner Controls:**
```javascript
const CrossfadeControls = () => {
  return (
    <div className="crossfade-controls">
      <label>Crossfade Duration:</label>
      <input 
        type="range" 
        min="0" 
        max="8000" 
        value={crossfadeDuration}
        onChange={(e) => setCrossfadeDuration(e.target.value)}
      />
      <span>{crossfadeDuration}ms</span>
      
      <button onClick={() => setCrossfadeEnabled(!crossfadeEnabled)}>
        {crossfadeEnabled ? 'Disable' : 'Enable'} Crossfade
      </button>
      
      <select value={crossfadeType} onChange={(e) => setCrossfadeType(e.target.value)}>
        <option value="smooth">Smooth (3s)</option>
        <option value="quick">Quick (1s)</option>
        <option value="long">Long (8s)</option>
        <option value="beat-match">Beat Match (4s)</option>
      </select>
    </div>
  );
};
```

### Crossfade Benefits for AJB

**Enhanced Party Experience:**
- **Seamless transitions** - No awkward silence between songs
- **Professional DJ-like feel** - Smooth mixing capabilities
- **Customizable timing** - Adjust to party mood and music style
- **Genre-aware crossfading** - Different fade times for different music types

**Technical Advantages:**
- **Overlapping playback** - Next song starts before current ends
- **Precise timing control** - Web Audio API provides sample-accurate timing
- **Real-time mixing** - No pre-processing required
- **Memory efficient** - Only loads next song when needed

**User Experience:**
- **Owner controls** - Full control over crossfade settings
- **Automatic mode** - Smart crossfading based on song characteristics
- **Manual override** - Instant crossfade when needed
- **Visual feedback** - Crossfade progress indicators

### Cross-Platform Compatibility

**Target Platforms:**
- **Desktop**: Chrome, Edge, Safari (with power-saving considerations)
- **Mobile**: iOS Safari, Android Chrome
- **Tablets**: iPad, Android tablets

**Modern Browser Requirements:**
- Web Audio API support
- Local storage capabilities
- WebSocket/SSE support
- No legacy browser support required

## iOS Autoplay Limitations - Technical Explanation

**What "Limited Autoplay" Means:**

Modern iOS Safari has strict autoplay policies to prevent websites from playing audio without user consent. Here's what this means for AJB:

**The Problem:**
- iOS Safari blocks automatic audio playback until user interaction
- This prevents seamless music transitions
- Background audio requires specific user gestures

**The Solution for AJB:**
- **Initial User Gesture**: First play button click satisfies iOS requirement
- **Subsequent Playback**: Once user has interacted, audio can continue automatically
- **Web Audio API**: Provides more control than HTML5 audio for programmatic playback
- **Service Worker**: Can help maintain audio context across page interactions

**Implementation Strategy:**
```javascript
// Initial user interaction unlocks audio
const unlockAudio = () => {
  const audioContext = new AudioContext();
  const buffer = audioContext.createBuffer(1, 1, 22050);
  const source = audioContext.createBufferSource();
  source.buffer = buffer;
  source.connect(audioContext.destination);
  source.start(0);
  audioContext.close();
};

// After unlock, normal playback continues
const playNextSong = () => {
  if (audioContext.state === 'suspended') {
    audioContext.resume();
  }
  // Continue with normal playback
};
```

**Why This Works for AJB:**
- Owner initiates playback with button click (satisfies iOS requirement)
- Once started, player maintains audio context
- No interruption to continuous playback
- Works seamlessly for party scenarios

**iOS Safari Autoplay Settings:**
- Users can enable autoplay per-website in Safari Settings
- For private apps like AJB, users should be instructed to allow autoplay
- We can detect and warn users if autoplay is blocked

**Technical Implementation:**
```javascript
// Detect iOS Safari and check autoplay capability
const detectIOSAutoplay = async () => {
  if (/iPad|iPhone|iPod/.test(navigator.userAgent)) {
    try {
      const audioContext = new AudioContext();
      const buffer = audioContext.createBuffer(1, 1, 22050);
      const source = audioContext.createBufferSource();
      source.buffer = buffer;
      source.connect(audioContext.destination);
      source.start(0);
      audioContext.close();
      return true; // Autoplay allowed
    } catch (error) {
      return false; // Autoplay blocked
    }
  }
  return true; // Not iOS, assume autoplay works
};

// Show user-friendly message if autoplay is blocked
const checkAutoplayCapability = async () => {
  const canAutoplay = await detectIOSAutoplay();
  if (!canAutoplay) {
    showIOSAutoplayInstructions();
  }
};

const showIOSAutoplayInstructions = () => {
  // Show modal with instructions:
  // "To enable continuous music playback on iOS Safari:
  //  1. Tap the 'aA' button in the address bar
  //  2. Tap 'Website Settings'
  //  3. Enable 'Auto-Play' for this site"
};
```

**User Instructions for iOS Safari:**
- Clear documentation that users need to enable autoplay for archive.cavaforge.net
- In-app detection and guidance for first-time iOS users
- Fallback messaging if autoplay detection fails

## Deployment Architecture

### Virtual Host Routing

**Domain Structure:**
- `archive.cavaforge.net` - Main archive interface
- `jukebox.cavaforge.net` - Party guest interface
- Both point to same Rails application

**Rails Routing Strategy:**
```ruby
# routes.rb
constraints subdomain: 'jukebox' do
  # Jukebox-specific routes
  root 'jukebox#index'
  resources :parties, only: [:show, :create]
  resources :queues, only: [:show, :update]
end

constraints subdomain: 'archive' do
  # Archive-specific routes
  root 'archive#index'
  resources :admin_parties
  resources :player_deployments
end
```

### Player Deployment Process

**"Start" Process (vs Play/Stop):**
1. User clicks "Start Player" on Archive.cavaforge.net
2. Rails generates unique session ID and API credentials
3. React SPA loads in browser with session context
4. Player establishes WebSocket connection to Archive
5. Player begins pre-downloading first song in queue
6. Player ready for "Play" command

**Deploy and Forget:**
- Single deployment per party session
- Local storage maintains session state
- Cookies preserve login status
- WebSocket maintains real-time connection
- No re-deployment needed during party

## Database Schema Design

### Multi-Tenant Architecture

**Core Principle:** Complete party isolation with scoped queries

### New Tables Required

**parties**
```sql
CREATE TABLE parties (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id VARCHAR(255) UNIQUE NOT NULL,
  password_hash VARCHAR(255),
  owner_id UUID REFERENCES users(id),
  name VARCHAR(255) NOT NULL,
  status VARCHAR(50) DEFAULT 'active', -- active, paused, ended
  start_time TIMESTAMP,
  end_time TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);
```

**party_queues**
```sql
CREATE TABLE party_queues (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  party_id UUID REFERENCES parties(id) ON DELETE CASCADE,
  song_id UUID REFERENCES songs(id),
  requested_by VARCHAR(255), -- guest username
  order_number INTEGER NOT NULL,
  status VARCHAR(50) DEFAULT 'queued', -- queued, playing, played, skipped
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_party_queues_party_order ON party_queues(party_id, order_number);
```

**party_playback_history**
```sql
CREATE TABLE party_playback_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  party_id UUID REFERENCES parties(id),
  song_id UUID REFERENCES songs(id),
  played_at TIMESTAMP DEFAULT NOW(),
  duration_seconds INTEGER,
  skipped BOOLEAN DEFAULT FALSE,
  requested_by VARCHAR(255)
);

CREATE INDEX idx_party_history_party_date ON party_playback_history(party_id, played_at);
```

**party_guests**
```sql
CREATE TABLE party_guests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  party_id UUID REFERENCES parties(id) ON DELETE CASCADE,
  guest_name VARCHAR(255) NOT NULL,
  joined_at TIMESTAMP DEFAULT NOW(),
  last_active TIMESTAMP DEFAULT NOW()
);
```

### Modified Existing Tables

**songs** (no changes needed - already has UUIDs)

**users** (no changes needed - already has UUIDs)

## API Design

### Party Management Endpoints

**Create Party**
```
POST /api/v1/parties
{
  "name": "Sister's Wedding Reception",
  "password": "optional_password",
  "start_time": "2024-01-15T18:00:00Z",
  "end_time": "2024-01-15T23:00:00Z"
}

Response:
{
  "success": true,
  "data": {
    "party": {
      "id": "uuid",
      "session_id": "sisters-wedding-reception",
      "name": "Sister's Wedding Reception",
      "status": "active"
    },
    "api_key": "party_specific_api_key"
  }
}
```

**Get Party Status**
```
GET /api/v1/parties/{session_id}

Response:
{
  "success": true,
  "data": {
    "party": { ... },
    "current_song": { ... },
    "queue": [ ... ],
    "guests_online": 5
  }
}
```

### Queue Management Endpoints

**Add Song to Queue**
```
POST /api/v1/parties/{session_id}/queue
{
  "song_id": "uuid",
  "requested_by": "guest_username"
}

Response:
{
  "success": true,
  "data": {
    "queue_item": {
      "id": "uuid",
      "song": { ... },
      "order_number": 5,
      "requested_by": "guest_username"
    }
  }
}
```

**Get Queue**
```
GET /api/v1/parties/{session_id}/queue

Response:
{
  "success": true,
  "data": {
    "queue": [
      {
        "id": "uuid",
        "song": { ... },
        "order_number": 1,
        "status": "queued",
        "requested_by": "guest_username"
      }
    ]
  }
}
```

### Audio Streaming Endpoints

**Download Song File**
```
GET /api/v1/songs/{song_id}/download
Headers: Authorization: Bearer {party_api_key}

Response: Binary audio file (MP3/M4A/FLAC)
```

**Get Song Metadata**
```
GET /api/v1/songs/{song_id}
Headers: Authorization: Bearer {party_api_key}

Response:
{
  "success": true,
  "data": {
    "song": {
      "id": "uuid",
      "title": "Song Title",
      "artist_name": "Artist",
      "album_name": "Album",
      "duration": 240,
      "file_format": "mp3",
      "file_size": 15728640
    }
  }
}
```

## Real-Time Communication

### WebSocket Implementation

**Connection**
```javascript
const ws = new WebSocket(`wss://archive.cavaforge.net/ws/party/${sessionId}`);
```

**Message Types**
```javascript
// Client to Server
{
  "type": "playback_status",
  "data": {
    "current_song_id": "uuid",
    "position": 120,
    "volume": 80,
    "is_playing": true
  }
}

// Server to Client
{
  "type": "queue_updated",
  "data": {
    "queue": [...],
    "current_song": {...}
  }
}

{
  "type": "song_requested",
  "data": {
    "song": {...},
    "requested_by": "guest_username"
  }
}
```

## Local Storage Strategy

### Modern Web Storage APIs

**IndexedDB for Permanent Audio Storage**
```javascript
// Store downloaded audio files permanently
const audioStore = {
  async storeAudio(songId, audioBlob) {
    const db = await openDB('ajb_audio', 1);
    const tx = db.transaction('audio_files', 'readwrite');
    // Store with metadata for cache management
    await tx.store.put({
      songId: songId,
      audioBlob: audioBlob,
      downloadedAt: Date.now(),
      fileSize: audioBlob.size
    }, songId);
  },
  
  async getAudio(songId) {
    const db = await openDB('ajb_audio', 1);
    const result = await db.get('audio_files', songId);
    return result ? result.audioBlob : null;
  },
  
  async isAudioCached(songId) {
    const db = await openDB('ajb_audio', 1);
    const result = await db.get('audio_files', songId);
    return result !== undefined;
  },
  
  // Cache management - clear old files if storage gets full
  async manageCache() {
    const db = await openDB('ajb_audio', 1);
    const tx = db.transaction('audio_files', 'readwrite');
    const store = tx.objectStore('audio_files');
    
    // Get storage usage and clear old files if needed
    const usage = await navigator.storage.estimate();
    const quota = usage.quota;
    const used = usage.usage;
    
    if (used > quota * 0.9) { // Clear cache when 90% full
      await this.clearOldestFiles();
    }
  }
};
```

**Service Worker for Offline Capability**
```javascript
// service-worker.js - Cache audio files for offline playback
self.addEventListener('fetch', event => {
  if (event.request.url.includes('/api/v1/songs/') && 
      event.request.url.includes('/download')) {
    event.respondWith(
      caches.open('ajb-audio-cache').then(cache => {
        return cache.match(event.request).then(response => {
          if (response) {
            return response; // Serve from cache
          }
          
          return fetch(event.request).then(fetchResponse => {
            // Cache the audio file for future use
            cache.put(event.request, fetchResponse.clone());
            return fetchResponse;
          });
        });
      })
    );
  }
});
```

**Cache-First Strategy**
```javascript
// Always check cache first, download only if not cached
const getAudioForPlayback = async (songId) => {
  // Check if already cached
  const cachedAudio = await audioStore.getAudio(songId);
  if (cachedAudio) {
    console.log(`Playing ${songId} from cache`);
    return cachedAudio;
  }
  
  // Download and cache for future use
  console.log(`Downloading ${songId} for first time`);
  const response = await fetch(`/api/v1/songs/${songId}/download`);
  const audioBlob = await response.blob();
  await audioStore.storeAudio(songId, audioBlob);
  
  return audioBlob;
};
```

**SessionStorage for Party State**
```javascript
// Maintain party session across page reloads
const partyState = {
  sessionId: 'sisters-wedding-reception',
  apiKey: 'party_api_key',
  currentSong: {...},
  queue: [...]
};
```

## Implementation Phases

### Phase 1: MVP (Minimum Viable Product)
- [ ] Basic React SPA with Howler.js
- [ ] Party creation and management
- [ ] Simple queue system
- [ ] Basic audio playback
- [ ] WebSocket real-time updates

### Phase 2: Core Features
- [ ] Complete file download and caching
- [ ] Pre-download next song functionality
- [ ] Admin controls (skip, remove, bump)
- [ ] Guest interface for song requests
- [ ] QR code generation for easy access

### Phase 3: Polish & Optimization
- [ ] Mobile-optimized UI
- [ ] Advanced audio features
- [ ] Playback history and analytics
- [ ] Performance optimizations
- [ ] Error handling and recovery

### Phase 4: Advanced Features
- [ ] Multiple simultaneous parties
- [ ] Party scheduling and management
- [ ] Advanced guest features
- [ ] Integration with existing Archive features

## Security Considerations

### Party Isolation
- All queries scoped to party_id
- API keys party-specific
- No cross-party data access
- Session timeouts and cleanup

### Guest Access Control
- Session ID + password authentication
- No persistent user accounts for guests
- Temporary access only
- Automatic cleanup after party ends

## Performance Targets

### Audio Quality
- Full bitrate playback (no compression)
- Complete file downloads before playback
- 5-10 second pre-download buffer
- No audio artifacts or interruptions

### Responsiveness
- < 100ms UI response time
- < 1 second song transition time
- Real-time queue updates
- Efficient memory usage

### Scalability
- Support for 3-5 simultaneous parties
- 15-20 concurrent users per party
- Efficient database queries
- Optimized WebSocket connections

---

*This document represents the alpha version of the Archive Jukebox design. It will evolve as implementation progresses and requirements are refined.*
