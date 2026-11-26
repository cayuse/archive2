# Comprehensive Guide to Two-Way Synchronization for a Music Archive System

This guide provides step-by-step instructions for cloning and synchronizing a music archive system consisting of a Rails application, a PostgreSQL database, and a large music file storage directory. The setup uses **Bucardo** for two-way (multi-master) PostgreSQL database replication and **Syncthing** for two-way file synchronization of the music directory, all running in Docker containers. The system is designed for one primary server (e.g., `cavaforgepad` with initial data) and any number of client machines (e.g., `jukebox` or additional clients) for two-way synchronization.

## Assumptions
- **Environment**: Development, Linux-based (e.g., Ubuntu).
- **Primary Server**: `cavaforgepad` (IP: 192.168.1.201).
- **Client Machine(s)**: e.g., `jukebox` (IP: 192.168.1.161), repeatable for additional clients.
- **Docker**: Installed with Docker Compose on all machines.
- **Network**: VPN (e.g., WireGuard) for secure communication (no public exposure).
- **PostgreSQL**: Version 15, database `archive_production`.
- **Users**:
  - PostgreSQL: `postgres` (password: `postgres_pass`), `bucardo` (password: `bucardo_pass`).
  - System user: `cayuse`.
- **Paths**:
  - Music directory: `/path/to/music` (host, mounted in Docker).
  - Rails app: `/home/cayuse/archive2/archive`.
- **SSH**: Passwordless access between machines for initial cloning (using SSH keys).
- **Database Tables**: 22 tables in `public` schema (e.g., `songs`, `albums`, `active_storage_*`), all synced initially.

## Warnings
- Two-way database sync may cause conflicts if the same data is modified simultaneously on multiple machines. Bucardo’s `bucardo_latest` strategy (last update wins) is used; consider app-level locking for production.
- Test thoroughly in development before production.
- Back up all data before starting.

## Prerequisites
1. **Set Up SSH Keys** (for initial cloning):
   - On `cavaforgepad`:
     ```bash
     ssh-keygen -t rsa -b 4096 -C "cayuse@cavaforgepad" -f ~/.ssh/id_rsa_music_sync
     ssh-copy-id -i ~/.ssh/id_rsa_music_sync.pub cayuse@192.168.1.161
     ```
   - Repeat for additional clients, replacing IP.
   - Test: `ssh cayuse@192.168.1.161` (should log in without password).

2. **Create Docker Network** (on all machines):
   ```bash
   docker network create music_archive_network
   ```

3. **Backup Data**:
   - Database: `docker compose exec db pg_dump -U postgres archive_production > /tmp/archive_production_backup.sql`
   - Music files: `rsync -avz /path/to/music /path/to/backup/`

## Part 1: Primary Server Setup (cavaforgepad)
Configure `cavaforgepad` (192.168.1.201) to host Bucardo and serve as the primary data source.

### Step 1: Install Dependencies
**Explanation**: Install Bucardo, Perl modules, and PostgreSQL client tools on the host for database replication and connectivity.
```bash
sudo apt update
sudo apt install -y bucardo postgresql-client libdbix-safe-perl libboolean-perl libdbd-pg-perl libdbi-perl postgresql-plperl-15
sudo mkdir -p /var/run/bucardo /var/log/bucardo
sudo touch /var/log/bucardo/log.bucardo
sudo chown cayuse /var/run/bucardo /var/log/bucardo
```

### Step 2: Configure PostgreSQL in Docker
**Explanation**: Set up the PostgreSQL container to host `archive_production` and `bucardo` databases, expose it to the host and VPN, and configure authentication.
- Create/edit `docker-compose.yml` in `/home/cayuse/archive2/archive`:
  ```yaml
  version: '3'
  services:
    db:
      image: postgres:15
      ports:
        - "0.0.0.0:5432:5432"
      environment:
        POSTGRES_PASSWORD: postgres_pass
        POSTGRES_DB: archive_production
        AWS_SES_SMTP_USERNAME: ""
        AWS_SES_SMTP_PASSWORD: ""
      volumes:
        - /path/to/pgdata:/var/lib/postgresql/data
      networks:
        - music_archive_network
      command: >
        bash -c "
          apt-get update &&
          apt-get install -y postgresql-plperl-15 &&
          exec docker-entrypoint.sh postgres
        "
    rails:
      image: archive:latest
      ports:
        - "0.0.0.0:3000:3000"
      environment:
        AWS_SES_SMTP_USERNAME: ""
        AWS_SES_SMTP_PASSWORD: ""
      volumes:
        - /path/to/music:/app/music
        - .:/app
      depends_on:
        - db
      networks:
        - music_archive_network
  networks:
    music_archive_network:
      external: true
  ```
- Start: `docker compose up -d`.
- Create `bucardo` user:
  ```bash
  docker compose exec db psql -U postgres -c "CREATE USER bucardo WITH SUPERUSER PASSWORD 'bucardo_pass';" || docker compose exec db psql -U postgres -c "ALTER USER bucardo WITH SUPERUSER PASSWORD 'bucardo_pass';"
  ```
- Edit `/path/to/pgdata/pg_hba.conf`:
  ```
  local all all trust
  host all all 127.0.0.1/32 trust
  host all all ::1/128 trust
  host archive_production bucardo 192.168.1.0/24 md5
  host archive_production postgres 192.168.1.0/24 md5
  host bucardo bucardo 127.0.0.1/32 md5
  host all all all scram-sha-256
  ```
- Edit `/path/to/pgdata/postgresql.conf`:
  ```
  listen_addresses = '*'
  ```
- Reload: `docker compose exec db psql -U postgres -c "SELECT pg_reload_conf();"`
- Test connectivity:
  ```bash
  psql -h 127.0.0.1 -U bucardo -d archive_production -W  # Enter bucardo_pass
  ```

### Step 3: Set Up Bucardo Metadata Database
**Explanation**: Create a separate `bucardo` database for Bucardo’s replication metadata and install its schema.
```bash
docker compose exec db psql -U postgres -c "DROP DATABASE IF EXISTS bucardo;"
docker compose exec db psql -U postgres -c "CREATE DATABASE bucardo OWNER bucardo;"
bucardo install
```
- Press `P` to proceed with defaults (Host: `localhost`, Port: `5432`, User: `bucardo`, Database: `bucardo`).
- Enter `bucardo_pass` when prompted.

### Step 4: Configure .pgpass for Authentication
**Explanation**: Store credentials for Bucardo and PostgreSQL to enable passwordless connections.
```bash
echo "127.0.0.1:5432:bucardo:bucardo:bucardo_pass" > /home/cayuse/.pgpass
echo "192.168.1.201:5432:archive_production:bucardo:bucardo_pass" >> /home/cayuse/.pgpass
# Add client IPs (e.g., jukebox)
echo "192.168.1.161:5432:archive_production:bucardo:bucardo_pass" >> /home/cayuse/.pgpass
chmod 600 /home/cayuse/.pgpass
```

### Step 5: Set Up Syncthing in Docker
**Explanation**: Configure Syncthing to sync the music directory bidirectionally with clients.
- Create `syncthing-docker-compose.yml` in `/home/cayuse/archive2/archive`:
  ```yaml
  version: "3"
  services:
    syncthing:
      image: syncthing/syncthing:latest
      container_name: syncthing
      hostname: cavaforgepad-syncthing
      environment:
        - PUID=1000
        - PGID=1000
        - TZ=Etc/UTC
      volumes:
        - /path/to/music:/var/syncthing/music
        - /path/to/syncthing/config:/var/syncthing/config
      ports:
        - 8384:8384
        - 22000:22000/tcp
        - 22000:22000/udp
        - 21027:21027/udp
      networks:
        - music_archive_network
      restart: unless-stopped
  networks:
    music_archive_network:
      external: true
  ```
- Start: `docker compose -f syncthing-docker-compose.yml up -d`.
- Access Syncthing GUI: `http://192.168.1.201:8384`, set a password (Settings > GUI).

## Part 2: Client Setup (e.g., jukebox, Repeat for Additional Clients)
Configure each client (e.g., `jukebox`, 192.168.1.161) to mirror the primary and participate in two-way sync.

### Step 1: Install Dependencies
**Explanation**: Install PostgreSQL client and Perl dependencies for database connectivity.
```bash
sudo apt update
sudo apt install -y postgresql-client libdbi-perl postgresql-plperl-15
```

### Step 2: Set Up PostgreSQL in Docker
**Explanation**: Mirror the primary’s PostgreSQL setup for `archive_production`.
- Copy `docker-compose.yml` from `cavaforgepad` to `/home/cayuse/archive2/archive` on `jukebox`:
  ```bash
  rsync -avz cayuse@192.168.1.201:/home/cayuse/archive2/archive/docker-compose.yml /home/cayuse/archive2/archive/
  ```
- Start: `docker compose up -d db`.
- Create `bucardo` user:
  ```bash
  docker compose exec db psql -U postgres -c "CREATE USER bucardo WITH SUPERUSER PASSWORD 'bucardo_pass';" || docker compose exec db psql -U postgres -c "ALTER USER bucardo WITH SUPERUSER PASSWORD 'bucardo_pass';"
  ```
- Update `/path/to/pgdata/pg_hba.conf` and `/path/to/pgdata/postgresql.conf` as in primary Step 2.
- Reload: `docker compose exec db psql -U postgres -c "SELECT pg_reload_conf();"`.

### Step 3: Clone Initial Data from Primary
**Explanation**: Copy the database, Rails app, and music files to bootstrap the client.
- **Database**:
  - On `cavaforgepad` (generate dump):
    ```bash
    docker compose exec db pg_dump -U postgres archive_production > /tmp/archive_production_dump.sql
    scp /tmp/archive_production_dump.sql cayuse@192.168.1.161:/tmp/
    ```
  - On `jukebox`:
    ```bash
    docker compose exec db psql -U postgres -d postgres -c "CREATE DATABASE archive_production;"
    docker compose exec db psql -U postgres -d archive_production < /tmp/archive_production_dump.sql
    ```
- **Rails App**:
  ```bash
  rsync -avz cayuse@192.168.1.201:/home/cayuse/archive2/archive/ /home/cayuse/archive2/archive/
  docker compose up -d
  ```
- **Music Files** (initial copy):
  ```bash
  rsync -avz cayuse@192.168.1.201:/path/to/music/ /path/to/music/
  ```

### Step 4: Set Up Syncthing in Docker
**Explanation**: Configure Syncthing to sync music files with the primary and other clients.
- Copy `syncthing-docker-compose.yml` from `cavaforgepad`, change hostname to `jukebox-syncthing`.
- Start: `docker compose -f syncthing-docker-compose.yml up -d`.
- In Syncthing GUI (`http://192.168.1.161:8384`):
  - Get Device ID from `cavaforgepad`’s GUI (Actions > Show ID).
  - Add Remote Device: Paste `cavaforgepad`’s ID, set address `tcp://192.168.1.201:22000`.
  - Add Folder: `/var/syncthing/music`, label "Music Archive", share with `cavaforgepad`.
  - On `cavaforgepad` GUI, accept the folder share.
  - Repeat for additional clients, adding their Device IDs.

## Part 3: Configure Two-Way Sync (Run on cavaforgepad)
Configure Bucardo on the primary server to manage multi-master replication for all machines.

### Step 1: Add Databases to Bucardo
**Explanation**: Register the primary and client databases in Bucardo for replication.
```bash
bucardo add database cavaforgepad dbname=archive_production host=192.168.1.201 port=5432 user=bucardo password=bucardo_pass
bucardo add database jukebox dbname=archive_production host=192.168.1.161 port=5432 user=bucardo password=bucardo_pass
# For additional clients, e.g., client2 at 192.168.1.162:
bucardo add database client2 dbname=archive_production host=192.168.1.162 port=5432 user=bucardo password=bucardo_pass
```

### Step 2: Add Tables to Sync
**Explanation**: Add all tables to the replication herd, excluding unwanted ones later if needed.
```bash
bucardo add all tables --herd=archive_herd --db=cavaforgepad
bucardo add all tables --herd=archive_herd --db=jukebox
# Repeat for additional clients, e.g.:
bucardo add all tables --herd=archive_herd --db=client2
```

### Step 3: Add Syncs for Multi-Master Replication
**Explanation**: Create bidirectional syncs between the primary and each client. For multiple clients, create a full mesh if all should sync with each other.
```bash
bucardo add sync cava_to_juke relgroup=archive_herd dbs=cavaforgepad:source,jukebox:target conflict_strategy=bucardo_latest
bucardo add sync juke_to_cava relgroup=archive_herd dbs=jukebox:source,cavaforgepad:target conflict_strategy=bucardo_latest
# For additional clients, e.g., client2:
bucardo add sync cava_to_client2 relgroup=archive_herd dbs=cavaforgepad:source,client2:target conflict_strategy=bucardo_latest
bucardo add sync client2_to_cava relgroup=archive_herd dbs=client2:source,cavaforgepad:target conflict_strategy=bucardo_latest
# Optional full mesh (between clients):
bucardo add sync juke_to_client2 relgroup=archive_herd dbs=jukebox:source,client2:target conflict_strategy=bucardo_latest
bucardo add sync client2_to_juke relgroup=archive_herd dbs=client2:source,jukebox:target conflict_strategy=bucardo_latest
```
- `bucardo_latest` requires timestamp columns (e.g., `updated_at`). Check: `docker compose exec db psql -U postgres -d archive_production -c "\d songs"`. If missing, use `bucardo_first` or add timestamps.

### Step 4: Start and Verify Bucardo
**Explanation**: Start replication and confirm syncs are active.
```bash
bucardo start
bucardo status
```

## Part 4: Testing and Validation
### Step 1: Test Database Sync
**Explanation**: Verify two-way replication by inserting data on one machine and checking the other.
- On `cavaforgepad`:
  ```bash
  docker compose exec db psql -U postgres -d archive_production -c "INSERT INTO songs (title) VALUES ('Test Song Cava');"
  ```
- On `jukebox` (after 5–10 seconds):
  ```bash
  docker compose exec db psql -U postgres -d archive_production -c "SELECT * FROM songs WHERE title = 'Test Song Cava';"
  ```
- Reverse test (insert on `jukebox`, check `cavaforgepad`).

### Step 2: Test File Sync
**Explanation**: Verify Syncthing syncs music files bidirectionally.
- Add a file to `/path/to/music` on `cavaforgepad`.
- Check if it appears in `/path/to/music` on `jukebox` (via Syncthing GUI or `ls`).
- Reverse test by adding a file on `jukebox`.

### Step 3: Test Rails App
**Explanation**: Ensure the Rails app connects to the local database.
- On both machines, update `database.yml`:
  ```yaml
  default: &default
    adapter: postgresql
    encoding: unicode
    host: 127.0.0.1
    port: 5432
    database: archive_production
    username: postgres
    password: postgres_pass
  development:
    <<: *default
  production:
    <<: *default
  ```
- Test: `docker compose exec rails rails runner "puts ActiveRecord::Base.connection.execute('SELECT 1').to_a"`.

## Part 5: Optional Table Exclusions
**Explanation**: Exclude Rails-specific or unnecessary tables from Bucardo sync to reduce conflicts or overhead.
```bash
bucardo remove table public.ar_internal_metadata --db=cavaforgepad
bucardo remove table public.ar_internal_metadata --db=jukebox
bucardo remove table public.schema_migrations --db=cavaforgepad
bucardo remove table public.schema_migrations --db=jukebox
# Add more tables as needed, e.g., active_storage_*
bucardo reload
```

## Troubleshooting
- **Bucardo Errors**:
  - Check logs: `cat /var/log/bucardo/log.bucardo`.
  - Verify connectivity: `psql -h 192.168.1.161 -U bucardo -d archive_production -W`.
  - Ensure tables have primary keys: `docker compose exec db psql -U postgres -d archive_production -c "\dt+"`.
- **Syncthing Issues**:
  - Check GUI logs (`http://192.168.1.201:8384` or `192.168.1.161:8384`).
  - Verify VPN allows ports 22000, 21027.
- **Rails Errors**:
  - Suppress AWS SES warnings by setting environment variables in `docker-compose.yml`.
  - Check PostgreSQL connection: `docker logs archive-db-1`.

## Maintenance
- **Backups**: Schedule `pg_dump` and `rsync` for database and file backups.
- **Monitoring**: Use `bucardo status` and Syncthing GUI for sync status.
- **Scaling**: Add more clients by repeating Part 2 and adding syncs in Part 3.