# Archive Player

The Archive Player is a standalone Python service that handles music playback for the Archive jukebox system. It connects to Redis for commands and streams audio via the jukebox API using MPV for high-quality playback.

## Features

- **Redis Integration**: Receives play/pause/stop commands via Redis queue
- **MPV Audio Engine**: High-quality audio playback with broad format support  
- **Systemd Service**: Runs as a reliable system service with auto-restart
- **Real-time Status**: Reports playback status and progress to Redis
- **Volume Control**: Remote volume adjustment via Redis commands

# Installation

Clone the repo to a suitable location

    git clone git@github.com:cauuse/archive2.git /opt/archive2

Then, create a python virtualenv with a reasonably updated python version. Lets assume
python3.12

    cd /opt/archive2/player
    python3.12 -m venv .venv

After virtualenv is installed, start it in the current shell, then update pip and
update the requiremehts for the player app:

    source .venv/bin/activate
    pip install -U piop
    pip install -r requirements.txt

## Install System Dependencies

### Install MPV Media Player

MPV is required for audio playback. Install it using your system's package manager:

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install mpv python3.12 python3.12-venv
```

**Other Systems:**
- **macOS**: `brew install mpv`
- **Fedora/RHEL**: `sudo dnf install mpv python3`
- **Arch**: `sudo pacman -S mpv python`

### Audio System Requirements

⚠️ **Critical**: The player service requires access to your system's audio subsystem.

**Audio System Access:**
- The service user must have permission to access audio devices
- May require audio group membership (`audio`, `pulse-audio`, etc.)  
- Runtime audio session access (especially for systemd services)

**Common Audio Systems:**
- **PulseAudio**: Most desktop Linux distributions
- **PipeWire**: Modern distributions (Ubuntu 22.04+, Fedora 34+)
- **ALSA**: Direct hardware access (lower level)

**Troubleshooting Audio Issues:**
If you encounter "No audio output" or permission errors:
1. Check user audio group membership: `groups $USER`
2. Test MPV manually: `mpv --no-video /path/to/audio/file`
3. For systemd services: ensure `XDG_RUNTIME_DIR` is set
4. Consult your distribution's audio documentation

# Setup Configuration

Create a `.env` file in the player directory with your configuration settings:

```bash
cd ~/archive2/player
cat > .env << 'EOF'
# Player Configuration
# Redis Configuration (connect to jukebox Redis)
PLAYER_REDIS_HOST=localhost
PLAYER_REDIS_PORT=6379
PLAYER_REDIS_DB=1

# Jukebox API Configuration (connect to jukebox)
PLAYER_API_URL=http://localhost:3001/api

# Audio Configuration
PLAYER_VOLUME=80
PLAYER_MPV_SOCKET=/tmp/player_mpv.sock
PLAYER_CACHE_SECS=20

# Redis Keys (match jukebox defaults)
PLAYER_STATUS_KEY=jukebox:player_status
PLAYER_CMD_LIST=jukebox:commands
PLAYER_CUR_SONG=jukebox:current_song
PLAYER_DESIRED=jukebox:desired_state
EOF
```

## Configuration Options

### Core Settings

- **PLAYER_REDIS_HOST**: Redis server hostname (default: `localhost`)
- **PLAYER_REDIS_PORT**: Redis server port (default: `6379`)
- **PLAYER_REDIS_DB**: Redis database number (default: `1`)
- **PLAYER_API_URL**: Jukebox API endpoint (default: `http://localhost:3001/api`)

### Audio Settings

- **PLAYER_VOLUME**: Initial volume 0-100 (default: `80`)
- **PLAYER_MPV_SOCKET**: MPV IPC socket path (default: `/tmp/player_mpv.sock`)
- **PLAYER_CACHE_SECS**: Audio cache duration (default: `20`)

### Advanced Configuration

For remote connections or SSH tunnels, modify the connection settings:

**SSH Tunnel Example:**
```bash
# If using SSH tunnel: local:3011 -> remote:3001
PLAYER_API_URL=http://localhost:3011/api
PLAYER_REDIS_PORT=3012  # If Redis is also tunneled
```

**Direct Network Connection:**
```bash
# Direct connection to remote jukebox
PLAYER_API_URL=http://192.168.1.100:3001/api
PLAYER_REDIS_HOST=192.168.1.100
```

# Running the application

The "player" app is in a subdirectory of the 'archive2' repo.
For the sake of this discussion, the location that you extract
the archive2 repository shall be called "REPO_ROOT".

The player subdirectory is then $REPO_ROOT/player, but I'll call that
$PLAYER_ROOT. IF this was all in a bash script, and we assume
the repo is extracted to /home/kutenai/proj/archive2, then you have

    export REPO_ROOT=/home/kutenai/proj/archive2
    export PLAYER_ROOT=$REPO_ROOT/player

I will assume that the $PLAYER_ROOT env variable is setup from now on.

So, we want to install a python virtualenv in $PLAYER_ROOT.

## Install VirtualENV

I have no idea what you are running on. On a standard *nix disti, like Ubuntu,
you can use `sudo apt install python3` or be more specific,
`sudo apt install python3.12`. What is available may vary, and you can
enable some other repods to get more recent versions. This app should
not require cuttying edge python. 3.12 is fine, 3.11 will work, even 3.10. 

You also need to install the venv for the python, so your install will be these two lines

    sudo apt install python3.12 python3.23-venv

Now, you have a working python3.12 (or whatever version you happened to use)

Create a virtualenv

    cd $PLAYER_ROOT
    python3.23 -m venv .venv

Now, I'm explicitely calling the 3.12, and i'm using the `-m` to use the 'venv' module,
and giving it the single argument `.venv`. The name of that virtualenv is just
convention, call it `.tiddlywinks` or `ilovecats`..  don't care. But, letting
you know it's just a name.

## Configure virtual environment modules
You can easiy test this out by running from the command line

    cd $PLAYER_ROOT
    source .venv/bin/activate

The above commands will "activate" the python virtualenv IN THE CURRENT SHELL. Nowhere else. This is
just a local thing. It sets some shell variables, that's it. and it adds the $PLAYER_ROOT/.venv/bin to your
path. So, now, just "python" will run the python from that virtualenv, and, use whatever modules you
have configured. So, the first thing I always do when I setup a new virtualenv is update pip.

    pip install -U pip

Now, you can install the requirements

    pip install -r requirements.txt

At this point, your virtual is created, activated (for this shell), and has the required modules installed.

## Run the player in your shell

Anytime you want to run the player, you can use the following commands. I'll assume this is a new shell,
but $PLAYER_ROOT is defined -- or you use the full path. This is how to run the app

    cd $PLAYER_ROOT
    source .venv/bin/activate
    python -m player.main

I sourced the environment, than used the raw python, that is now in the path. I could have done this
instead:

    cd $PLAYER_ROOT
    .venv/bin/python -m player.main

I do not 'NEED' the environment to be source, that's just a convenience, once python is running, it
won't ned that path.

Finally, I can just do this also

    $PLAYER_ROOT/.venv/bin/python -m player.main

Full path provided. Now, that above won't work properly if the "working directory" is not $PLAYER_ROOT,
that is because the `-m player.main` assumes there is a python module in the current directory.

Inside that module there is a file named `main.py`, and that is what you are "running". Technically, you are
importing the module player.main, and that will auto-run

## Run the player in your shell "as a script"
I've been running the player as a module.
If you wanted to run it as a "script", you'd have to have a
wrapper of some sort. A very simple wrapper would be a `run.py` script

    ./player/run.py

That would like like this


    from player.main import main

    main()

You could then run this from anywhere

    cd ~
    $PLAYER_ROOT/.venv/bin/python $PLAYER_ROOT/run.py

The trick there is that you'd need to make sure you copied the 
`.env` file to the local path where you run it, so these 
values would work. In otherwords, the system expects to find
a .env file in the current working directory.




# System Service

I have provided an *EXAMPLE* systemd service file. This file
is installed by copying to /etc/systemd/system. 

THIS IS AN EXAMPLE!!

## Modify the file to match your local environment
First, set the "WorkingDirectory" to match your install
location. This will be the `PLAYER_ROOT` value, but it will NOT
be an environment variable, provide the full path here.

Next, you will need the `ExecStart` line to match your environment.
This is easy, since the service will have the working directory in the player
location, where you have already created the virtrual env, it should
just work like the example.

## Systemd Service Installation

### Service User Configuration

**Recommended Approach**: Run the service as your console user (e.g., `cayuse`) to ensure audio system access:

```bash
# Edit the systemd service file before installation
sudo nano ~/archive2/player/systemd/archive_player.service

# Update these lines:
User=cayuse          # Replace with your username
Group=cayuse         # Replace with your group
WorkingDirectory=/home/cayuse/archive2/player  # Update path
ExecStart=/home/cayuse/archive2/player/.venv/bin/python -m player.main  # Update path

# Add audio environment (for systemd services):
Environment="XDG_RUNTIME_DIR=/run/user/1000"  # Replace 1000 with your UID
Environment="PULSE_RUNTIME_PATH=/run/user/1000/pulse"
```

**Alternative**: Create a dedicated `player` system user and add to audio groups:
```bash
sudo useradd --system --shell /bin/false --home /opt/archive2/player player
sudo usermod -a -G audio,pulse-audio player  # Add to audio groups
```

### Install the Service

```bash
# Copy service file to systemd
sudo cp ~/archive2/player/systemd/archive_player.service /etc/systemd/system/

# Reload systemd and enable service
sudo systemctl daemon-reload
sudo systemctl enable archive_player.service
sudo systemctl start archive_player.service
```

### Verify Installation

Check if the service is running:
```bash
sudo systemctl status archive_player
```

Monitor logs:
```bash
sudo journalctl -n 100 -f -u archive_player
```

### Service Management Commands

```bash
# Start/stop/restart service
sudo systemctl start archive_player
sudo systemctl stop archive_player  
sudo systemctl restart archive_player

# Enable/disable auto-start
sudo systemctl enable archive_player
sudo systemctl disable archive_player

# View recent logs
sudo journalctl -u archive_player -n 50

# Follow logs in real-time
sudo journalctl -u archive_player -f
```


