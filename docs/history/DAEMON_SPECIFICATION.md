# Project Specification: Jukebox Daemon v2.0 ("Jooki-Linux")

## 1. High-Level Vision & Architecture

**Objective:** Create a headless audio player daemon for Linux to replace the original Objective-C macOS application. The daemon will run continuously, manage a dynamic music queue, and be controlled remotely by an existing Ruby on Rails front-end application.

**Core Architecture:** A two-part system:

1.  **Playback Engine: Music Player Daemon (MPD)**
    *   **Technology:** The standard `mpd` package.
    *   **Role:** A dedicated, high-performance audio playback engine.
    *   **Responsibilities:**
        *   Playing audio streams from URLs.
        *   Managing low-level audio buffers and hardware interaction.
        *   Executing sample-perfect crossfades between tracks based on its configuration.

2.  **Control Logic: Ruby Script (The "Conductor")**
    *   **Technology:** A persistent Ruby script.
    *   **Role:** The "brain" of the application, containing all custom logic.
    *   **Responsibilities:**
        *   Connecting to and commanding the MPD instance.
        *   Communicating with the Rails front-end via a REST API and a Redis-based message queue.
        *   Implementing the primary control loop for just-in-time song queuing.

This architecture delegates playback to a specialized, robust C++ tool (MPD), while keeping the flexible application logic in Ruby to align with the existing project ecosystem.

## 2. Component Breakdown

### 2.1. Music Player Daemon (MPD)

*   **Role:** Playback server.
*   **Key Responsibilities:** Play audio from URLs, execute crossfades.
*   **Configuration (`mpd.conf`):**
    *   `music_directory`: Point to a dummy location (e.g., `/var/lib/mpd/music`). We are not using local file-based library features.
    *   `audio_output`: Configure for the target Linux audio system (e.g., ALSA or PulseAudio).
    *   `crossfade`: Set to the desired default crossfade duration in seconds (e.g., `6`).
    *   `bind_to_address`: `127.0.0.1` (for security).
    *   `zeroconf_enabled`: `no`.

### 2.2. The Ruby "Conductor" Script

*   **Role:** Central control process.
*   **Primary Logic:**
    1.  **Initialization:**
        *   Load configuration from a `.env` file (API endpoints, keys, Redis URL).
        *   Establish persistent connections to MPD and Redis.
        *   Subscribe to the Redis command channel.
    2.  **Main Control Loop:** A high-frequency loop (`~10Hz`, i.e., `sleep 0.1`) that constitutes the script's primary runtime behavior.
        *   **Check for IPC Commands:** Process any pending commands from the Redis queue.
        *   **Check Playback Status:**
            *   Query `mpd.status`.
            *   If playing, calculate `time_remaining = duration - elapsed_time`.
            *   If `time_remaining` is below a threshold (e.g., `10.0` seconds) AND the MPD queue length is `1` (or less), trigger the song fetching logic.
*   **Dependencies (Gemfile):**
    *   `ruby-mpd`: For MPD communication.
    *   `redis`: For Redis Pub/Sub communication.
    *   `httparty` or `faraday`: For making API calls to the Rails front-end.
    *   `dotenv`: For managing environment variables from a `.env` file.
*   **Song Fetching Logic (`fetch_and_enqueue_next_song`):**
    1.  Make an authenticated `GET` request to the Rails API (e.g., `GET /api/v1/next_song`).
    2.  The Rails API returns a JSON object: `{ "url": "...", "title": "...", "artist": "..." }`.
    3.  The Conductor script adds the received URL to MPD's queue via `mpd.add(song_url)`.

### 2.3. Rails Front-End API

*   **Role:** Source of truth for playlists and song metadata.
*   **Required Endpoints:**
    *   **`GET /api/v1/next_song`**
        *   **Action:** Executes the business logic for selecting the next track (priority > request > random).
        *   **Authentication:** Requires a static Bearer Token.
        *   **Success Response:** `200 OK` with JSON body: `{ "url": "http://path/to/song.mp3", "title": "Song Title", "artist": "Artist Name" }`.
        *   **Failure/Empty Response:** `204 No Content`.

### 2.4. Inter-Process Communication (IPC)

*   **Technology:** Redis Pub/Sub.
*   **Channel Name:** `jukebox:commands`.
*   **Message Format:** JSON strings.
    *   **Examples:**
        *   `{ "command": "pause" }`
        *   `{ "command": "play" }`
        *   `{ "command": "skip" }`
        *   `{ "command": "set_volume", "level": 85 }`
        *   `{ "command": "play_next_immediately", "song_url": "..." }`
*   **Flow:** Rails Controller -> `Redis.publish` -> Conductor Redis Subscriber -> Conductor Command Handler -> `ruby-mpd` action.

## 3. Deployment & Operation

*   **Service Management:** The Conductor script will be managed by a **`systemd`** service.
*   **Service File (`jooki-conductor.service`):**
    *   `Description=Jukebox Conductor Daemon`
    *   `ExecStart=/usr/bin/env ruby /path/to/conductor.rb`
    *   `WorkingDirectory=/path/to/project`
    *   `Restart=always`
    *   `RestartSec=10`
    *   `User=jukebox` (or other non-privileged user).
*   **Logging:** The service will log to `journald`, accessible via `journalctl -u jooki-conductor.service`.

## 4. Implementation Plan

1.  **Phase 1: Environment Setup & Basic Control**
    *   [ ] Install `mpd` and `redis-server`.
    *   [ ] Configure `mpd.conf`.
    *   [ ] Initialize the Ruby project with a `Gemfile` and `.env` file.
    *   [ ] Write a basic script to connect to MPD and test core commands (`play`, `pause`, `add`, `status`).

2.  **Phase 2: Conductor Core Loop**
    *   [ ] Implement the main timer loop (`loop do ... sleep 0.1`).
    *   [ ] Add logic to query MPD status and calculate `time_remaining`.
    *   [ ] Implement the song-fetching trigger condition.
    *   [ ] Stub `fetch_and_enqueue_next_song` to add a hardcoded URL.
    *   [ ] Test the core just-in-time queuing behavior.

3.  **Phase 3: API Integration**
    *   [ ] Implement the `GET /api/v1/next_song` endpoint in the Rails application.
    *   [ ] Update the Conductor's `fetch_and_enqueue_next_song` to call the live API endpoint.

4.  **Phase 4: IPC Command & Control**
    *   [ ] Implement the Redis subscriber logic in the Conductor to listen on the `jukebox:commands` channel.
    *   [ ] Implement a command handler `case` statement to map incoming JSON commands to MPD actions.
    *   [ ] Implement the publisher logic in the Rails application.
    *   [ ] Test all commands end-to-end.

5.  **Phase 5: Deployment & Hardening**
    *   [ ] Create and install the `systemd` service file.
    *   [ ] Implement comprehensive error handling (e.g., for failed API calls, Redis disconnects).
    *   [ ] Add structured logging throughout the script.
    *   [ ] Perform long-duration stability testing.
