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


