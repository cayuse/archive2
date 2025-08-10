# Deployment Guide

## Overview

This system consists of two applications with a shared architecture:

1. **Archive** - Central music repository with PostgreSQL, Redis, and storage
2. **Jukebox** - Music player that connects to Archive's services

Archive must be deployed first, as Jukebox depends on its PostgreSQL database, Redis, and storage.
Both applications use Docker containers with Apache2 as a reverse proxy.

## Architecture

### Archive Deployment
```
┌─────────────────────────────────────┐
│           Apache2                   │
│         (Reverse Proxy)             │
│    archive.yourdomain.com           │
└─────────────────┬───────────────────┘
                  │
    ┌─────────────┴─────────────┐
    │      Docker Compose       │
    │                           │
    │  ┌─────────┐ ┌─────────┐  │
    │  │ Archive │ │   PG    │  │
    │  │ :3000   │ │ :5432   │  │
    │  └─────────┘ └─────────┘  │
    └───────────────────────────┘
```

### Jukebox Deployment
```
┌─────────────────────────────────────┐
│           Apache2                   │
│         (Reverse Proxy)             │
│    jukebox.yourdomain.com           │
└─────────────────┬───────────────────┘
                  │
    ┌─────────────┴─────────────┐
    │      Docker Compose       │
    │                           │
    │  ┌─────────┐ ┌─────────┐  │
    │  │ Jukebox │ │   MPD   │  │
    │  │ :3001   │ │ :6600   │  │
    │  └─────────┘ └─────────┘  │
    │  ┌─────────────────────┐  │
    │  │   Python Player     │  │
    │  └─────────────────────┘  │
    └───────────────────────────┘
                  │
    ┌─────────────┴─────────────┐
    │      Archive Services     │
    │  ┌─────────┐ ┌─────────┐  │
    │  │   PG    │ │  Redis  │  │
    │  │ :5432   │ │ :6379   │  │
    │  └─────────┘ └─────────┘  │
    └───────────────────────────┘
```

## Prerequisites

### System Requirements
- Ubuntu 20.04+ or Debian 11+
- Docker and Docker Compose
- Apache2 (installed automatically by deployment scripts)
- 2GB RAM minimum (4GB recommended)
- 10GB disk space minimum

### Network Requirements
- Port 80/443 open for web traffic
- Port 3000/3001 for direct container access (optional)
- DNS configured for your domains

## Deployment Order and Dependencies

**IMPORTANT**: Archive must be deployed and running before Jukebox can be deployed.

### Dependencies
- **Archive** provides:
  - PostgreSQL database (shared)
  - Redis cache (shared)
  - Music file storage (shared)
  - User authentication and management
  - Music metadata and processing

- **Jukebox** requires:
  - Archive's PostgreSQL database
  - Archive's Redis instance
  - Archive's storage directory
  - Archive's running Rails application

## Deployment Options

### Networking and SSL modes

- Direct port (testing/dev): Access the app at http://SERVER_IP:3000 without a reverse proxy.
  - Recommended env for testing with an IP and HTTP:
    ```bash
export RAILS_MASTER_KEY=...               # required
export POSTGRES_PASSWORD=...              # required
export HOST_STORAGE_PATH=/abs/path/storage
export POSTGRES_DATA_PATH=/abs/path/pg
export ARCHIVE_PORT=3000                  # host port → container 3000
export APP_HOST=SERVER_IP                 # e.g. 192.168.1.201
export APP_PROTOCOL=http
export FORCE_SSL=false
export ASSUME_SSL=false
export FORGERY_ORIGIN_CHECK=false         # disable strict CSRF origin for IP testing
export ALLOW_ALL_HOSTS=true               # accept any Host header during testing
docker compose up -d --build
    ```

- Reverse proxy (production): Keep the container listening on 3000 and front it with Apache/Nginx on 80/443, terminating TLS.
  - Recommended env for production behind TLS:
    ```bash
export ARCHIVE_PORT=80                    # optional; only if you also publish host 80 → container 3000
export APP_HOST=archive.yourdomain.com
export APP_PROTOCOL=https
export FORCE_SSL=true
export ASSUME_SSL=true
export FORGERY_ORIGIN_CHECK=true
export ALLOW_ALL_HOSTS=false
docker compose up -d --build
    ```
  - See Apache/Nginx examples below; point the proxy to http://127.0.0.1:3000.

### Database persistence and first-time setup

- Persistence:
  - `POSTGRES_DATA_PATH` is the on-host directory for PostgreSQL data.
  - `HOST_STORAGE_PATH` is the on-host directory for file storage.
- First-time DB init:
  - The `archive/deploy.sh` script checks if the DB is initialized (via `schema_migrations`). If empty, it runs `rails db:prepare` and, when `AUTO_SEED=true`, `rails db:seed`.
  - Force a re-run if needed:
    ```bash
export FORCE_DB_SETUP=true   # override the check
export AUTO_SEED=true        # optional
./deploy.sh --production
    ```

### Port mapping options

- Default container port: 3000 (non-root inside the container).
- Host port can be changed via `ARCHIVE_PORT` (e.g., 80 for convenience):
  ```bash
export ARCHIVE_PORT=80
docker compose up -d --build
  ```

### Security notes for production

- Do not expose PostgreSQL or Redis publicly. In Compose, either remove the `ports:` block or bind to localhost only (e.g., `127.0.0.1:5432:5432`).
- Prefer a reverse proxy on 80/443 with TLS termination. Keep the Rails container on 3000.
- Remove the `version:` line from `docker-compose.yml` to silence Compose v2 warnings.

### Option 1: Deploy Archive Only
```bash
cd archive
export RAILS_MASTER_KEY=your_master_key_here
export POSTGRES_PASSWORD=your_secure_password
export HOST_STORAGE_PATH=/path/to/your/music/storage
export POSTGRES_DATA_PATH=/path/to/your/postgres/data
./deploy.sh
```

### Option 2: Deploy Both on Same Server (Recommended)
```bash
# Deploy Archive first
cd archive
export RAILS_MASTER_KEY=your_master_key_here
export POSTGRES_PASSWORD=your_secure_password
export HOST_STORAGE_PATH=/path/to/your/music/storage
export POSTGRES_DATA_PATH=/path/to/your/postgres/data
./deploy.sh

# Deploy Jukebox second (after Archive is running)
cd ../jukebox
export RAILS_MASTER_KEY=your_master_key_here
export POSTGRES_PASSWORD=your_secure_password
./deploy.sh
```

### Option 3: Deploy on Separate Servers
```bash
# Server 1: Deploy Archive
cd archive
export RAILS_MASTER_KEY=your_master_key_here
export POSTGRES_PASSWORD=your_secure_password
export HOST_STORAGE_PATH=/path/to/your/music/storage
export POSTGRES_DATA_PATH=/path/to/your/postgres/data
./deploy.sh

# Server 2: Deploy Jukebox (pointing to Archive server)
cd jukebox
export RAILS_MASTER_KEY=your_master_key_here
export POSTGRES_PASSWORD=your_secure_password
export ARCHIVE_SERVER_URL=http://archive-server-ip:3000
export ARCHIVE_DB_HOST=archive-server-ip
export ARCHIVE_REDIS_HOST=archive-server-ip
export ARCHIVE_STORAGE_PATH=/path/to/shared/storage
./deploy.sh
```

## Environment Variables

### Archive Required
- `RAILS_MASTER_KEY` - Rails master key for credentials

### Archive Optional
- `POSTGRES_PASSWORD` - PostgreSQL password (default: password)
- `HOST_STORAGE_PATH` - Host path for music files (default: ./storage)
- `POSTGRES_DATA_PATH` - Host path for PostgreSQL data (default: ./postgres_data)

### Jukebox Required
- `RAILS_MASTER_KEY` - Rails master key for credentials
- `POSTGRES_PASSWORD` - Must match Archive's PostgreSQL password

### Jukebox Optional
- `ARCHIVE_SERVER_URL` - URL of Archive server (default: http://localhost:3000)
- `ARCHIVE_DB_HOST` - Archive database host (default: localhost)
- `ARCHIVE_DB_PORT` - Archive database port (default: 5432)
- `ARCHIVE_REDIS_HOST` - Archive Redis host (default: localhost)
- `ARCHIVE_REDIS_PORT` - Archive Redis port (default: 6379)
- `ARCHIVE_STORAGE_PATH` - Path to Archive's storage (default: ../archive/storage)
- `JUKEBOX_CLIENT_ID` - Unique client identifier (default: jukebox-1)

## Docker Images and Services

### Archive Services
- **archive** (Rails app): `ghcr.io/rails/devcontainer/images/ruby:3.3.8`
  - Ports: 3000 (Rails)
  - Features: Includes ffmpeg for audio processing
  - Volumes: Storage, logs

- **db** (PostgreSQL): `postgres:15`
  - Ports: 5432 (PostgreSQL)
  - Volumes: Database data (configurable path)
  - Environment: Configurable password

- **redis**: `redis:7-alpine`
  - Ports: 6379 (Redis)
  - Volumes: Redis data

- **sidekiq** (Background jobs): Uses archive image
  - Purpose: Music processing, metadata extraction
  - Dependencies: Database, Redis, Archive app

### Jukebox Services
- **jukebox** (Rails app): `ruby:3.3.8-slim`
  - Ports: 3001 (Rails)
  - Dependencies: Archive's PostgreSQL, Redis, storage
  - Volumes: Logs, Archive storage (read-only)

- **mpd** (Music Player Daemon): `mpd:latest`
  - Ports: 6600 (MPD)
  - Purpose: Audio playback and playlist management
  - Volumes: MPD data, playlists, Archive storage (read-only)

- **jukebox-player** (Python controller): `python:3.11-slim`
  - Purpose: Controls MPD, manages queue, communicates with Jukebox API
  - Dependencies: MPD, Jukebox Rails app
  - Volumes: Logs

## Apache2 Configuration

### Modules Required
- `proxy` - Reverse proxy functionality
- `proxy_http` - HTTP proxy support
- `headers` - Security headers
- `deflate` - Compression
- `expires` - Caching headers

### Virtual Hosts
- Archive: `archive.yourdomain.com` → `localhost:3000`
- Jukebox: `jukebox.yourdomain.com` → `localhost:3001`

### Security Features
- X-Content-Type-Options: nosniff
- X-Frame-Options: DENY
- X-XSS-Protection: enabled
- Compression enabled
- Static asset caching

## Storage Configuration

### Archive Storage
Archive manages the central storage for all music files. Configure the storage path during deployment:

```bash
export HOST_STORAGE_PATH="/path/to/your/music/files"
export POSTGRES_DATA_PATH="/path/to/your/postgres/data"
```

**Important**: 
- Use absolute paths for production deployments
- Ensure the storage directory contains your music files
- The PostgreSQL data directory should be on a reliable storage device
- Both paths will be mounted into Docker containers

### Jukebox Storage Access
Jukebox accesses Archive's storage in read-only mode:
- Music files are served from Archive's storage
- Jukebox mounts the same storage directory
- No duplicate storage needed
- Ensures consistency between applications

## SSL/HTTPS Setup

1. **Obtain SSL certificates** (Let's Encrypt recommended)
2. **Update Apache2 configs**:
   ```bash
   sudo nano /etc/apache2/sites-available/archive.conf
   sudo nano /etc/apache2/sites-available/jukebox.conf
   ```
3. **Uncomment SSL sections** and update certificate paths
4. **Enable SSL modules**:
   ```bash
   sudo a2enmod ssl
   sudo a2enmod rewrite
   ```
5. **Restart Apache2**:
   ```bash
   sudo systemctl restart apache2
   ```

## Monitoring and Maintenance

### Health Checks
- Archive: `curl http://localhost:3000/up`
- Jukebox: `curl http://localhost:3001/api/jukebox/health`

### Logs
```bash
# Archive logs
cd archive && docker-compose logs -f

# Jukebox logs
cd jukebox && docker-compose logs -f

# Apache2 logs
sudo tail -f /var/log/apache2/archive_error.log
sudo tail -f /var/log/apache2/jukebox_error.log
```

### Updates
```bash
# Archive update
cd archive
git pull
docker-compose up -d --build

# Jukebox update
cd jukebox
git pull
docker-compose up -d --build
```

### Backup
```bash
# Archive database backup
cd archive
docker-compose exec db pg_dump -U postgres archive_production > backup.sql

# Jukebox data backup
cd jukebox
docker-compose exec jukebox tar czf jukebox-backup.tar.gz /rails/storage
```

## Troubleshooting

### Common Issues

1. **Port conflicts**
   ```bash
   # Check what's using ports
   sudo netstat -tlnp | grep :3000
   sudo netstat -tlnp | grep :3001
   sudo netstat -tlnp | grep :5432
   sudo netstat -tlnp | grep :6379
   sudo netstat -tlnp | grep :6600
   ```

2. **Archive not running when deploying Jukebox**
   ```bash
   # Check Archive status
   curl -f http://localhost:3000/up
   
   # If Archive is down, start it first
   cd archive && docker-compose up -d
   ```

3. **Database connection issues**
   ```bash
   # Check PostgreSQL logs
   cd archive && docker-compose logs db
   
   # Verify connection from Jukebox
   cd jukebox && docker-compose exec jukebox rails console
   # In console: ActiveRecord::Base.connection.execute("SELECT 1")
   ```

4. **Redis connection issues**
   ```bash
   # Check Redis logs
   cd archive && docker-compose logs redis
   
   # Verify connection from Jukebox
   cd jukebox && docker-compose exec jukebox rails console
   # In console: Redis.new.ping
   ```

5. **Storage access issues**
   ```bash
   # Check if storage is mounted correctly
   cd jukebox && docker-compose exec jukebox ls -la /rails/storage
   
   # Verify Archive storage path
   cd archive && docker-compose exec archive ls -la /rails/storage
   ```

6. **MPD connection issues**
   ```bash
   # Check MPD logs
   cd jukebox && docker-compose logs mpd
   
   # Test MPD connection
   docker-compose exec mpd mpc status
   ```

7. **Python player issues**
   ```bash
   # Check player logs
   cd jukebox && docker-compose logs jukebox-player
   
   # Verify player is running
   docker-compose exec jukebox-player pgrep -f player.py
   ```

8. **Apache2 configuration errors**
   ```bash
   # Test configuration
   sudo apache2ctl configtest
   ```

### Performance Tuning

1. **Increase PostgreSQL memory** (in docker-compose.yml):
   ```yaml
   environment:
     POSTGRES_SHARED_BUFFERS: 256MB
     POSTGRES_EFFECTIVE_CACHE_SIZE: 1GB
   ```

2. **Enable Redis persistence** (in docker-compose.yml):
   ```yaml
   command: redis-server --appendonly yes
   ```

3. **Apache2 worker tuning** (in apache2.conf):
   ```apache
   StartServers 2
   MinSpareServers 2
   MaxSpareServers 10
   MaxRequestWorkers 150
   ```

## Security Considerations

1. **Change default passwords** immediately after deployment
2. **Use strong PostgreSQL passwords**
3. **Configure firewall** to restrict access
4. **Enable SSL/TLS** for production
5. **Regular security updates** for Docker images
6. **Monitor logs** for suspicious activity

## Support

For issues and questions:
1. Check the logs first
2. Verify environment variables
3. Test individual components
4. Review this deployment guide
5. Check the main documentation files 