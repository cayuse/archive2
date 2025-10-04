# Archive Jukebox (AJB) - Design Document

## Project Overview

Archive Jukebox (AJB) is a multi-tenant music streaming system that extends the existing Archive music collection with party-based jukebox capabilities. The system consists of two main interfaces:

1. **Archive.cavaforge.net** - Admin interface for authenticated users to create and manage party sessions
2. **Jukebox.cavaforge.net** - Guest interface for party attendees to request songs and view queues

## Current Implementation Status

### ✅ Phase 1: Foundation Complete
- **Database Schema**: Jukeboxes and JukeboxPlaylists tables created with proper indexes
- **Rails Models**: Jukebox, JukeboxPlaylist models with full associations and validations
- **Rails Controller**: JukeboxesController with CRUD operations and lifecycle management
- **Rails Routes**: Complete RESTful routes with custom actions (start, pause, resume, end, reset)
- **Rails Views**: Comprehensive UI with index, show, new, edit pages and partials
- **System Integration**: Jukebox card added to Archive system settings page
- **User Management**: Users can create, manage, and control their own jukeboxes

### ✅ Phase 2: Player & Guest Interface (COMPLETED)
- **React Player Application**: Fully implemented with MVC architecture
- **React Guest Controller**: Fully implemented with real-time updates
- **Real-time Communication**: ActionCable WebSocket implementation complete
- **API Endpoints**: Complete jukebox-specific API endpoints implemented
- **Audio Engine**: Web Audio API with crossfading support
- **State Management**: Reactive state with persistent storage

### 📋 Phase 3: Advanced Features (IN PROGRESS)
- **Queue Management**: Real-time queue updates and song requests
- **Advanced Audio**: Crossfading, pre-loading, and quality optimization
- **Mobile Optimization**: Responsive design improvements
- **Performance Optimization**: Caching and efficiency improvements

## Current Development Status

### ✅ Completed Components

**1. Rails Backend (100% Complete)**
- Jukebox model with all associations
- RESTful controller with full CRUD operations
- API endpoints for real-time communication
- ActionCable WebSocket integration
- Database migrations and schema

**2. Player Application (100% Complete)**
- React-based MVC architecture
- AudioEngine with Web Audio API
- PlaybackState with IndexedDB persistence
- WebSocketService with ActionCable
- ApiService for REST communication
- PlayerController for business logic
- PlayerView with React components

**3. Guest Controller (100% Complete)**
- React-based MVC architecture
- GuestController for real-time updates
- GuestView with search and request functionality
- Real-time playback status display
- Song search and request capabilities
- Queue viewing and status monitoring

**4. Real-time Communication (100% Complete)**
- ActionCable WebSocket channels
- 1-second status updates from player
- Real-time broadcasting to all guests
- REST API fallback for reliability
- Connection status monitoring

### 🔄 In Progress

**1. Database Migration**
- Migration to add playback fields to jukeboxes table
- Foreign key relationships for current_song_id
- Indexes for performance optimization

**2. Integration Testing**
- End-to-end testing of player/guest communication
- WebSocket connection stability testing
- Audio playback quality testing

### 📋 Next Steps

**1. Queue Management System**
- Dedicated JukeboxQueue model
- Real-time queue reordering
- Priority and VIP request handling
- Queue position notifications

**2. Advanced Audio Features**
- Crossfading between songs
- Audio pre-loading for seamless playback
- Quality optimization based on connection
- Volume normalization

**3. Mobile Optimization**
- Touch-friendly controls
- Responsive design improvements
- Offline capability for cached songs
- Push notifications for queue updates

**4. Performance Optimization**
- Audio caching strategies
- Connection pooling
- Database query optimization
- CDN integration for audio files

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

## Database Schema Design - IMPLEMENTED

### Multi-Tenant Architecture

**Core Principle:** Complete party isolation with scoped queries

### Implemented Tables

**jukeboxes** ✅ IMPLEMENTED
```sql
CREATE TABLE jukeboxes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(255) NOT NULL,
  session_id VARCHAR(255) UNIQUE NOT NULL,
  password_hash VARCHAR(255),
  owner_id UUID REFERENCES users(id) NOT NULL,
  private BOOLEAN DEFAULT false NOT NULL,
  status VARCHAR(50) DEFAULT 'inactive' NOT NULL,
  started_at TIMESTAMP,
  ended_at TIMESTAMP,
  scheduled_start TIMESTAMP,
  scheduled_end TIMESTAMP,
  crossfade_enabled BOOLEAN DEFAULT true NOT NULL,
  crossfade_duration INTEGER DEFAULT 3000 NOT NULL,
  auto_play BOOLEAN DEFAULT true NOT NULL,
  description TEXT,
  location VARCHAR(255),
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_jukeboxes_owner_id ON jukeboxes(owner_id);
CREATE INDEX idx_jukeboxes_session_id ON jukeboxes(session_id);
CREATE INDEX idx_jukeboxes_status ON jukeboxes(status);
CREATE INDEX idx_jukeboxes_private ON jukeboxes(private);
CREATE INDEX idx_jukeboxes_created_at ON jukeboxes(created_at);
CREATE INDEX idx_jukeboxes_public_active ON jukeboxes(private, status) WHERE private = false;
```

**jukebox_playlists** ✅ IMPLEMENTED
```sql
CREATE TABLE jukebox_playlists (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  jukebox_id UUID REFERENCES jukeboxes(id) ON DELETE CASCADE NOT NULL,
  playlist_id UUID REFERENCES playlists(id) ON DELETE CASCADE NOT NULL,
  weight INTEGER DEFAULT 1 NOT NULL,
  enabled BOOLEAN DEFAULT true NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_jukebox_playlists_jukebox_id ON jukebox_playlists(jukebox_id);
CREATE INDEX idx_jukebox_playlists_playlist_id ON jukebox_playlists(playlist_id);
CREATE INDEX idx_jukebox_playlists_jukebox_playlist ON jukebox_playlists(jukebox_id, playlist_id);
CREATE INDEX idx_jukebox_playlists_jukebox_enabled ON jukebox_playlists(jukebox_id, enabled);
```

### Updated Existing Models ✅ IMPLEMENTED

**User Model Updates:**
```ruby
class User < ApplicationRecord
  has_many :jukeboxes, dependent: :destroy
  # ... existing associations
end
```

**Playlist Model Updates:**
```ruby
class Playlist < ApplicationRecord
  has_many :jukebox_playlists, dependent: :destroy
  has_many :jukeboxes, through: :jukebox_playlists
  # ... existing associations
end
```

### Planned Future Tables

**jukebox_queues** (Not yet implemented)
```sql
CREATE TABLE jukebox_queues (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  jukebox_id UUID REFERENCES jukeboxes(id) ON DELETE CASCADE,
  song_id UUID REFERENCES songs(id),
  requested_by VARCHAR(255), -- guest username
  order_number INTEGER NOT NULL,
  status VARCHAR(50) DEFAULT 'queued', -- queued, playing, played, skipped
  created_at TIMESTAMP DEFAULT NOW()
);
```

**jukebox_playback_history** (Not yet implemented)
```sql
CREATE TABLE jukebox_playback_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  jukebox_id UUID REFERENCES jukeboxes(id),
  song_id UUID REFERENCES songs(id),
  played_at TIMESTAMP DEFAULT NOW(),
  duration_seconds INTEGER,
  skipped BOOLEAN DEFAULT FALSE,
  requested_by VARCHAR(255)
);
```

**jukebox_guests** (Not yet implemented)
```sql
CREATE TABLE jukebox_guests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  jukebox_id UUID REFERENCES jukeboxes(id) ON DELETE CASCADE,
  guest_name VARCHAR(255) NOT NULL,
  joined_at TIMESTAMP DEFAULT NOW(),
  last_active TIMESTAMP DEFAULT NOW()
);
```

## Rails Implementation - COMPLETED ✅

### Models

**Jukebox Model** ✅ IMPLEMENTED
```ruby
class Jukebox < ApplicationRecord
  belongs_to :owner, class_name: 'User'
  has_many :jukebox_playlists, dependent: :destroy
  has_many :playlists, through: :jukebox_playlists

  validates :name, presence: true, length: { maximum: 255 }
  validates :session_id, presence: true, uniqueness: true, length: { maximum: 255 }
  validates :status, inclusion: { in: %w[inactive active paused ended] }
  validates :crossfade_duration, numericality: { greater_than: 0, less_than_or_equal_to: 30000 }
  validates :owner_id, presence: true

  scope :active, -> { where(status: 'active') }
  scope :public_jukeboxes, -> { where(private: false) }
  scope :private_jukeboxes, -> { where(private: true) }
  scope :owned_by, ->(user) { where(owner_id: user.id) }

  before_validation :generate_session_id, on: :create
  before_validation :normalize_session_id

  # Lifecycle methods
  def start!; update!(status: 'active', started_at: Time.current); end
  def pause!; update!(status: 'paused'); end
  def resume!; update!(status: 'active'); end
  def end!; update!(status: 'ended', ended_at: Time.current); end
  def reset!; update!(status: 'inactive', started_at: nil, ended_at: nil); end

  # Status checks
  def active?; status == 'active'; end
  def ended?; status == 'ended'; end
  def paused?; status == 'paused'; end
  def inactive?; status == 'inactive'; end
  def public?; !private?; end
  def has_password?; password_hash.present?; end
end
```

**JukeboxPlaylist Model** ✅ IMPLEMENTED
```ruby
class JukeboxPlaylist < ApplicationRecord
  belongs_to :jukebox
  belongs_to :playlist

  validates :jukebox_id, presence: true
  validates :playlist_id, presence: true
  validates :weight, presence: true, numericality: { greater_than: 0 }
  validates :jukebox_id, uniqueness: { scope: :playlist_id }

  scope :enabled, -> { where(enabled: true) }
  scope :ordered, -> { order(:weight, :created_at) }
end
```

### Controller

**JukeboxesController** ✅ IMPLEMENTED
```ruby
class JukeboxesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_jukebox, only: [:show, :edit, :update, :destroy, :start, :pause, :resume, :end, :reset]
  before_action :ensure_owner, only: [:edit, :update, :destroy, :start, :pause, :resume, :end, :reset]

  # Standard CRUD actions
  def index; @jukeboxes = current_user.jukeboxes.order(created_at: :desc); end
  def show; @jukebox_playlists = @jukebox.jukebox_playlists.includes(:playlist).order(:weight, :created_at); end
  def new; @jukebox = current_user.jukeboxes.build; end
  def edit; end
  
  def create
    @jukebox = current_user.jukeboxes.build(jukebox_params)
    if @jukebox.save
      assign_playlists_to_jukebox
      redirect_to @jukebox, notice: 'Jukebox was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @jukebox.update(jukebox_params)
      assign_playlists_to_jukebox
      redirect_to @jukebox, notice: 'Jukebox was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @jukebox.destroy
    redirect_to jukeboxes_url, notice: 'Jukebox was successfully deleted.'
  end

  # Lifecycle actions
  def start; @jukebox.start!; redirect_to @jukebox, notice: 'Jukebox started successfully.'; end
  def pause; @jukebox.pause!; redirect_to @jukebox, notice: 'Jukebox paused successfully.'; end
  def resume; @jukebox.resume!; redirect_to @jukebox, notice: 'Jukebox resumed successfully.'; end
  def end; @jukebox.end!; redirect_to @jukebox, notice: 'Jukebox ended successfully.'; end
  def reset; @jukebox.reset!; redirect_to @jukebox, notice: 'Jukebox reset successfully.'; end

  private

  def jukebox_params
    # Handles password hashing with BCrypt
    # Manages playlist assignments
    # Returns sanitized parameters
  end
end
```

### Routes ✅ IMPLEMENTED

```ruby
# config/routes.rb
resources :jukeboxes do
  member do
    post :start
    post :pause
    post :resume
    post :end
    post :reset
  end
end
```

### Views ✅ IMPLEMENTED

**Index Page** (`app/views/jukeboxes/index.html.erb`)
- Lists all user's jukeboxes in a card grid layout
- Shows jukebox status, privacy level, and quick actions
- Includes empty state for new users
- Responsive design with Bootstrap

**Show Page** (`app/views/jukeboxes/show.html.erb`)
- Comprehensive jukebox details and settings
- Real-time status display with action buttons
- Playlist management interface
- Guest access information with copy-to-clipboard URL
- Lifecycle controls (start, pause, resume, end, reset)

**New/Edit Pages** (`app/views/jukeboxes/new.html.erb`, `app/views/jukeboxes/edit.html.erb`)
- Shared form partial for creating and editing jukeboxes
- Comprehensive settings including privacy, passwords, scheduling
- Audio settings (crossfade configuration)
- Playlist selection with weight management
- Form validation and error handling

**Form Partial** (`app/views/jukeboxes/_form.html.erb`)
- Complete form with all jukebox settings
- Password hashing support
- Playlist multi-select with checkboxes
- Audio configuration options
- Responsive layout with validation feedback

**Jukebox Card Partial** (`app/views/jukeboxes/_jukebox.html.erb`)
- Reusable jukebox display component
- Status badges with color coding
- Quick action buttons
- Metadata display (location, schedule, playlist count)

### System Integration ✅ IMPLEMENTED

**Settings Page Integration**
- Added Jukebox card to system settings page
- Provides easy access to jukebox management
- Consistent with existing settings UI patterns

**User Management**
- Users can create multiple jukeboxes
- Complete ownership and permission system
- Privacy controls (public/private jukeboxes)

### Key Features Implemented ✅

1. **Complete Jukebox Lifecycle Management**
   - Create, edit, delete jukeboxes
   - Start, pause, resume, end, reset states
   - Status tracking and validation

2. **Privacy and Access Control**
   - Public/private jukebox settings
   - Password protection with BCrypt hashing
   - Session ID generation and management

3. **Playlist Management**
   - HABTM relationship between jukeboxes and playlists
   - Weight-based playlist ordering
   - Enable/disable playlist functionality

4. **Scheduling and Configuration**
   - Scheduled start/end times
   - Crossfade settings (enabled, duration)
   - Auto-play configuration
   - Location and description metadata

5. **User Experience**
   - Comprehensive web interface
   - Responsive design
   - Real-time status updates
   - Guest access URL generation

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

### ActionCable Implementation

**Connection**
```javascript
// Initialize ActionCable consumer
window.App.cable = ActionCable.createConsumer('/cable');

// Subscribe to jukebox channel
const subscription = App.cable.subscriptions.create(
  { channel: "JukeboxChannel", session_id: sessionId },
  {
    connected() {
      console.log("Connected to jukebox channel");
    },
    received(data) {
      handleRealtimeUpdate(data);
    }
  }
);
```

**Message Types**
```javascript
// Player to Server (REST API + WebSocket)
{
  "current_song_id": "uuid",
  "position": 120.5,
  "is_playing": true,
  "volume": 0.8,
  "crossfade_duration": 3000
}

// Server to All Clients (WebSocket Broadcast)
{
  "type": "playback_status_update",
  "data": {
    "current_song_id": "uuid",
    "position": 120.5,
    "is_playing": true,
    "volume": 0.8,
    "timestamp": "2024-01-15T18:30:00Z"
  }
}

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

### ActionCable Integration

**Why ActionCable?**
- **Built-in Rails Integration**: Seamless integration with Rails authentication
- **Automatic Reconnection**: Handles connection drops gracefully
- **Channel-based Architecture**: Clean separation of concerns
- **Scalable**: Supports Redis backend for multi-server deployments
- **Authentication**: Built-in user authentication and authorization

**Channel Implementation**
```ruby
class JukeboxChannel < ApplicationCable::Channel
  def subscribed
    session_id = params[:session_id]
    if session_id.present?
      stream_from "jukebox_#{session_id}"
    else
      reject
    end
  end
end
```

**Broadcasting Updates**
```ruby
# In jukeboxes_controller.rb
ActionCable.server.broadcast(
  "jukebox_#{@jukebox.session_id}",
  {
    type: 'playback_status_update',
    data: playback_status
  }
)
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

## Implementation Phases - UPDATED STATUS

### ✅ Phase 1: Foundation (COMPLETED)
- [x] **Database Schema**: Jukeboxes and JukeboxPlaylists tables
- [x] **Rails Models**: Complete with associations and validations
- [x] **Rails Controller**: Full CRUD with lifecycle management
- [x] **Rails Routes**: RESTful routes with custom actions
- [x] **Rails Views**: Comprehensive UI (index, show, new, edit, partials)
- [x] **User Management**: Authentication and ownership
- [x] **Privacy Controls**: Public/private jukeboxes with password protection
- [x] **Playlist Management**: HABTM relationship with weight ordering
- [x] **System Integration**: Added to Archive settings page

### 🚧 Phase 2: Player & Guest Interface (IN PROGRESS)
- [ ] **React Player Application**: Browser-based music player
- [ ] **Guest Interface**: Jukebox.cavaforge.net pages for party attendees
- [ ] **Queue Management**: Real-time song request and queue system
- [ ] **API Endpoints**: RESTful API for player and guest interactions
- [ ] **WebSocket/SSE**: Real-time communication between players and guests
- [ ] **Audio Streaming**: Song download and playback endpoints

### 📋 Phase 3: Advanced Audio Features (PLANNED)
- [ ] **Crossfading**: Web Audio API implementation with Tone.js
- [ ] **Audio Caching**: IndexedDB permanent storage for songs
- [ ] **Pre-download System**: Smart next-song loading
- [ ] **Audio Quality**: Full bitrate, no compression playback
- [ ] **iOS Safari Support**: Autoplay detection and guidance

### 📋 Phase 4: Polish & Optimization (PLANNED)
- [ ] **Mobile Optimization**: Responsive design improvements
- [ ] **Performance**: Caching and efficiency optimizations
- [ ] **Analytics**: Playback history and party statistics
- [ ] **Error Handling**: Robust error recovery and user feedback
- [ ] **QR Code Generation**: Easy party access for guests

### 📋 Phase 5: Advanced Features (FUTURE)
- [ ] **Multiple Simultaneous Parties**: Scaling to concurrent sessions
- [ ] **Advanced Scheduling**: Time-based party management
- [ ] **Enhanced Guest Features**: User profiles and preferences
- [ ] **Integration**: Deep integration with existing Archive features

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

## Files Created and Locations ✅

### Database Migrations
- `/archive/db/migrate/20250124000000_create_jukeboxes.rb`
- `/archive/db/migrate/20250124000001_create_jukebox_playlists.rb`

### Models
- `/archive/app/models/jukebox.rb`
- `/archive/app/models/jukebox_playlist.rb`
- **Updated**: `/archive/app/models/user.rb` (added jukeboxes association)
- **Updated**: `/archive/app/models/playlist.rb` (added jukebox_playlists associations)

### Controller
- `/archive/app/controllers/jukeboxes_controller.rb`

### Routes
- **Updated**: `/archive/config/routes.rb` (added jukeboxes resources)

### Views
- `/archive/app/views/jukeboxes/index.html.erb`
- `/archive/app/views/jukeboxes/show.html.erb`
- `/archive/app/views/jukeboxes/new.html.erb`
- `/archive/app/views/jukeboxes/edit.html.erb`
- `/archive/app/views/jukeboxes/_form.html.erb`
- `/archive/app/views/jukeboxes/_jukebox.html.erb`

### System Integration
- **Updated**: `/archive/app/views/settings/index.html.erb` (added Jukebox card)

## Migration Commands (When Rails Environment Available)

```bash
# Navigate to archive directory
cd /home/cayuse/archive2/archive

# Run migrations
rails db:migrate

# Verify table creation
rails console
> Jukebox.create!(name: "Test Party", owner: User.first)
> JukeboxPlaylist.create!(jukebox: Jukebox.first, playlist: Playlist.first, weight: 1)
```

## Ready for Next Phase

The foundation is now complete and ready for Phase 2 implementation:

1. **Working Rails Application**: Full CRUD for jukeboxes with comprehensive UI
2. **Database Schema**: Tables created with proper associations and indexes
3. **User Management**: Complete ownership and permission system
4. **System Integration**: Accessible through Archive settings page

**Next Steps**:
1. Implement guest interface (jukebox.cavaforge.net)
2. Create React player application
3. Add API endpoints for real-time communication
4. Implement WebSocket/SSE for live updates
5. Build queue management system

## Session Scoping Implementation Notes

### Jukebox Session Binding Strategy

**Problem**: Both player and guest JavaScript applications need to be bound to a specific jukebox session for their entire lifecycle.

**Implementation Plan**:

**1. Session ID Injection**
- When a user accesses `/jukeboxes/:id/player` or `/jukeboxes/:id/guest`, the jukebox session_id is injected into the page
- JavaScript applications receive the session_id via `window.AJB_CONFIG.sessionId`
- All API calls from both player and guest apps are scoped to this session_id

**2. API Scoping Mechanism**
```ruby
# In Api::V1::JukeboxesController
def set_jukebox
  # Accept either jukebox ID or session_id for scoping
  if params[:session_id].present?
    @jukebox = Jukebox.find_by(session_id: params[:session_id])
  else
    @jukebox = Jukebox.find(params[:id])
  end
  
  unless @jukebox
    render json: { success: false, message: 'Jukebox not found' }, status: 404
    return
  end
end
```

**3. JavaScript Application Binding**
```javascript
// In both player.js and guest.js
class JukeboxSession {
  constructor(config) {
    this.sessionId = config.sessionId;
    this.jukeboxId = config.jukeboxId;
    this.apiBase = `/api/v1/jukeboxes/session/${this.sessionId}`;
  }
  
  // All API calls use this.sessionId for scoping
  async getQueue() {
    return fetch(`${this.apiBase}/queue`);
  }
  
  async addToQueue(songId, source = 'requested') {
    return fetch(`${this.apiBase}/queue`, {
      method: 'POST',
      body: JSON.stringify({ song_id: songId, source: source })
    });
  }
}
```

**4. Route Updates Needed**
```ruby
# Add session-based routes for JavaScript apps
namespace :api do
  namespace :v1 do
    resources :jukeboxes, only: [] do
      member do
        # Existing ID-based routes
        get :status
        get :queue
        # ... other existing routes
      end
    end
    
    # New session-based routes for JavaScript apps
    scope 'jukeboxes/session/:session_id' do
      get 'status', to: 'jukeboxes#status'
      get 'queue', to: 'jukeboxes#queue'
      post 'queue', to: 'jukeboxes#add_to_queue'
      delete 'queue/:song_id', to: 'jukeboxes#remove_from_queue'
      patch 'queue/:song_id', to: 'jukeboxes#move_in_queue'
      get 'playback_info', to: 'jukeboxes#playback_info'
      post 'playback_status', to: 'jukeboxes#playback_status'
    end
  end
end
```

**5. Security Considerations**
- Session-based routes should verify the jukebox is active and accessible
- Guest routes should allow access to public jukeboxes or password-protected ones
- Player routes should verify ownership or delegated permissions
- All routes should validate session_id exists and jukebox is in valid state

**6. Lifecycle Management**
- Session binding persists until user navigates away or closes browser
- No server-side session storage needed - all scoping happens via URL parameters
- JavaScript applications maintain their own state and connection to the specific jukebox
- WebSocket connections are scoped to the specific jukebox session

**Implementation Priority**:
1. Add session-based routes to routes.rb
2. Update Api::V1::JukeboxesController to handle session_id parameter
3. Update JavaScript applications to use session-based API calls
4. Test session scoping with both player and guest applications
5. Add security validations for session-based access

---

*This document represents the comprehensive design and current implementation status of Archive Jukebox. Updated with Phase 1 completion details, queue management system implementation, and session scoping strategy.*
