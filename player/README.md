# Archive Player
The remove player app.
Takes song info from a redis queue, and plays the songs as they come up.


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

## Install MPV
This depends on your system. For my Mac, I used homebrew

    brew install mpv

That works

# Setup Configuration

Copy the .env.example file to .env
Modify the values as needed.
For example, I'm using "jukebox" via a tunnel, where port 3011 is the port
locally, and 3001 is remote. I have this in my ~/.ssh/config files

    Host archive-dave
    hostname archive.cavaforge.net
    user kutenai
    port 16597
    
        IdentityFile "/Users/edhenderson/.ssh/bondilabs/CavaForge SSH Key.pub"
        IdentitiesOnly true
    
        LocalForward 3010 localhost:3000
        LocalForward 3011 localhost:3001
        Localforward 3012 localhost:6379

So, my .env PLAYER_API_URL value is

    PLAYER_API_URL="http://localhost:3011/api"

Instead of default:

    PLAYER_API_URL="http://localhost:3001/api"

The same goes for my redis port

    PLAYER_REDIS_PORT=3012


# System Service

The systemd service will run with the installed systemd file. An example is located in the
systemd path. Install like this:

    cd /opt/archive2player
    cp systemd/archive_player.service /etc/systemd/system
    sudo systemctl daemon-reload
    sudo systemctl enable archive_player.service
    sudo systemctl start archive_player.service

Check if the service is running

    sudo systemctl status archive_player

Or, monitor it with journalctl

    sudo journalctl -n 100 -f -u archive_player


