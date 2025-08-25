# Archive Player
The song player app.
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

## Systemd file "User"

I added the "user". This is just an example also. The systemd service
will run as "root", but if you want it to run as something else, you can
create a user, i.e. "player" and run it as that. this is optional, but
probably recommended. Comment those lines out of you don't make this.

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


