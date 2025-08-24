# Deployment Guide

## Overview

This system consists of two applications with a shared architecture:

1. **Archive** - Central music repository with PostgreSQL, Redis, and storage
2. **Jukebox** - Music player interface that connects to Archive's services

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
    │  ┌─────────┐              │
    │  │ Jukebox │              │
    │  │ :3001   │              │
    │  └─────────┘              │
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

- **Direct port (testing/dev)**: Access the app at http://SERVER_IP:3000 without a reverse proxy.
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

- **Reverse proxy (production)**: Keep the container listening on 3000 and front it with Apache/Nginx on 80/443, terminating TLS.
  - Recommended env for production behind TLS:
    ```bash
export RAILS_MASTER_KEY=...               # required
export POSTGRES_PASSWORD=...              # required
export HOST_STORAGE_PATH=/abs/path/storage
export POSTGRES_DATA_PATH=/abs/path/pg
export ARCHIVE_PORT=3000                  # keep container on 3000, nginx proxies 80/443
export APP_HOST=archive.yourdomain.com    # your actual domain
export APP_PROTOCOL=https                 # use HTTPS
export FORCE_SSL=true                     # redirect HTTP to HTTPS
export ASSUME_SSL=true                    # assume SSL behind nginx
export FORGERY_ORIGIN_CHECK=true          # enable CSRF protection
export ALLOW_ALL_HOSTS=false              # only accept your domain
export AWS_SES_SMTP_USERNAME=...          # AWS SES credentials
export AWS_SES_SMTP_PASSWORD=...
docker compose up -d --build
    ```
  - **Nginx Configuration**: Create `/etc/nginx/sites-available/archive.yourdomain.com`:
    ```nginx
    server {
        listen 80;
        server_name archive.yourdomain.com;
        return 301 https://$server_name$request_uri;
    }
    
    server {
        listen 443 ssl http2;
        server_name archive.yourdomain.com;
        
        ssl_certificate /etc/letsencrypt/live/archive.yourdomain.com/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/archive.yourdomain.com/privkey.pem;
        
        location / {
            proxy_pass http://127.0.0.1:3000;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
    ```
  - **Let's Encrypt Setup**:
    ```bash
    # Install certbot
    sudo apt install certbot python3-certbot-nginx
    
    # Get initial certificate
    sudo certbot --nginx -d archive.yourdomain.com
    
    # Auto-renewal (add to crontab)
    sudo crontab -e
    # Add: 0 12 * * * /usr/bin/certbot renew --quiet
    ```
  - **Enable the site**:
    ```bash
    sudo ln -s /etc/nginx/sites-available/archive.yourdomain.com /etc/nginx/sites-enabled/
    sudo nginx -t
    sudo systemctl reload nginx
    ```

### Database persistence and first-time setup

- **Persistence**:
  - `POSTGRES_DATA_PATH` is the on-host directory for PostgreSQL data.
  - `HOST_STORAGE_PATH` is the on-host directory for file storage.
- **First-time DB init**:
  - The `archive/deploy.sh` script checks if the DB is initialized (via `schema_migrations`). If empty, it runs `rails db:prepare` and, when `AUTO_SEED=true`, `rails db:seed`.
  - Force a re-run if needed:
    ```bash
export FORCE_DB_SETUP=true   # override the check
export AUTO_SEED=true        # optional
./deploy.sh --production
    ```

### Important: First Login After Fresh Deployment

When deploying from scratch, the system creates a new admin user with a randomly generated UUID. Browsers often cache stale credentials, causing Rails to not recognize the new UUID. To resolve this:

```bash
# After successful deployment, first logout to clear any cached sessions:
http://<your-server-ip>:3000/logout

# Then visit the login page:
http://<your-server-ip>:3000/login

# This helps the system recognize the new UUID-based user account
# Default credentials (change immediately after first login):
# Email: admin@cavaforge.net
# Password: admin123
```

**Note**: This step is only necessary on fresh deployments. Subsequent deployments work normally. The logout step clears browser-cached credentials that may interfere with the new UUID-based user system.

### Port mapping options

- **Default container port**: 3000 (non-root inside the container).
- **Host port can be changed** via `ARCHIVE_PORT` (e.g., 80 for convenience):
  ```bash
export ARCHIVE_PORT=80
docker compose up -d --build
  ```

### Security notes for production

- **Do not expose PostgreSQL or Redis publicly**. In Compose, either remove the `ports:` block or bind to localhost only (e.g., `127.0.0.1:5432:5432`).
- **Prefer a reverse proxy on 80/443 with TLS termination**. Keep the Rails container on 3000.
- **Remove the `version:` line** from `docker-compose.yml` to silence Compose v2 warnings.

## Deployment Workflow

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
export HOST_STORAGE_PATH=/abs/path/to/archive/storage   # must be absolute
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
export ARCHIVE_DB_HOST=archive-server-ip
export ARCHIVE_REDIS_HOST=archive-server-ip
export HOST_STORAGE_PATH=/path/to/shared/storage
./deploy.sh
```

## Environment Variables

### Archive Required
- `RAILS_MASTER_KEY` - Rails master key for credentials

### Archive Optional
- `POSTGRES_PASSWORD` - PostgreSQL password (default: password)
- `HOST_STORAGE_PATH` - Host path for music files (default: ./storage)
- `POSTGRES_DATA_PATH` - Host path for PostgreSQL data (default: ./postgres_data)
- `ARCHIVE_PORT` - Host port for Archive (default: 3000 for dev, 80 for production)
- `APP_HOST` - Domain or IP for the application
- `APP_PROTOCOL` - Protocol (http or https)
- `FORCE_SSL` - Force SSL redirects (default: false)
- `ASSUME_SSL` - Assume SSL behind proxy (default: false)
- `FORGERY_ORIGIN_CHECK` - CSRF origin checking (default: true)
- `ALLOW_ALL_HOSTS` - Allow any Host header (default: false)

## Email Configuration

### AWS SES Setup

The Archive application is configured to use AWS SES (Simple Email Service) for sending emails. This includes welcome emails for new users and other system notifications.

#### Required AWS SES Environment Variables

```bash
# AWS SES SMTP Credentials (Required)
export AWS_SES_SMTP_USERNAME="your_aws_ses_smtp_username"
export AWS_SES_SMTP_PASSWORD="your_aws_ses_smtp_password"

# Optional AWS SES Configuration (have sensible defaults)
export AWS_SES_SMTP_HOST="email-smtp.us-east-2.amazonaws.com"
export AWS_SES_SMTP_PORT="587"
export AWS_SES_SMTP_DOMAIN="cavaforge.net"
export MAILER_FROM_EMAIL="noreply@cavaforge.net"
```

#### Setting Environment Variables

**Option 1: Export in your shell before deployment:**
```bash
export AWS_SES_SMTP_USERNAME="your_username"
export AWS_SES_SMTP_PASSWORD="your_password"
cd archive
./deploy.sh
```

**Option 2: Create a `.env` file in the archive directory:**
```bash
# archive/.env
AWS_SES_SMTP_USERNAME=your_aws_ses_smtp_username
AWS_SES_SMTP_PASSWORD=your_aws_ses_smtp_password
```

**Option 3: Pass directly to docker-compose:**
```bash
AWS_SES_SMTP_USERNAME=your_username AWS_SES_SMTP_PASSWORD=your_password docker compose up -d
```

#### Email Features Enabled

- **Welcome Emails**: Automatically sent when administrators create new user accounts
- **Professional Templates**: HTML email templates with CavaForge branding
- **AWS SES Delivery**: High deliverability and professional email service
- **From Address**: `noreply@cavaforge.net` (configurable via `MAILER_FROM_EMAIL`)

#### Testing Email Configuration

After deployment, test the email system by:
1. Creating a new user account through the admin interface
2. Checking if the welcome email is sent successfully
3. Verifying the email comes from `noreply@cavaforge.net`
4. Checking AWS SES console for delivery status

## Credentials Management

### Generating New Credentials from Scratch

When cloning a fresh repository that doesn't have `credentials.yml.enc` or `master.key`, you'll need to generate new 
Rails credentials. This can be done using Docker without installing Rails locally.

### NOTE make sure if you have old versions of either of those files you delete them before this procedure

#### Option 1: Using Docker Container (Recommended)

```bash
# Navigate to archive directory
cd archive

# Create a temporary container with Rails
docker run --rm -it -v $(pwd):/app -w /app ruby:3.2.5-slim bash

# Inside the container, install Rails and generate credentials
apt-get update && apt-get install -y build-essential
#gem install rails  < unnecessary, it will be installed by bundler>

# Bundle install is required because Rails demands it with existing Gemfile
bundle install

# Generate new credentials (this will show you the master key)
rails credentials:edit

# After generation, you'll see the master key (32 characters)
# Example: abc123def456ghi789jkl012mno345pqr678stu901vwx234yz567890

# Set the master key and edit credentials
export RAILS_MASTER_KEY=<paste_the_32_character_key_here>
VISUAL="code --wait" bin/rails credentials:edit
```

#### Option 2: Using Existing Docker Compose

If you already have the Docker setup working:

```bash
# Build the image first
docker compose build

# Generate new credentials
docker compose run --rm archive rails credentials:edit
```

#### What This Generates

1. **`master.key`** - 32-character random key (add to `.gitignore`)
2. **`credentials.yml.enc`** - Encrypted credentials file (safe to commit)

#### Important Notes

- **Bundle install is required** after `gem install rails` due to existing Gemfile
- **Two-step process**: First generate, then set master key and edit
- **Master key must be kept secure** and never committed to Git
- **Set `RAILS_MASTER_KEY`** environment variable to the generated key

#### After Generation

1. **Copy the master key** from the first command output
2. **Set it as environment variable** for your deployment
3. **Edit credentials** to add your configuration (AWS SES, etc.)
4. **Commit `credentials.yml.enc`** to Git
5. **Never commit `master.key`** (should be in `.gitignore`)


This procedure should also be done in the jukebox folder if you are going to deploy a jukebox


### Jukebox Required
- `RAILS_MASTER_KEY` - Rails master key for credentials
- `POSTGRES_PASSWORD` - Must match Archive's PostgreSQL password

### Jukebox Optional
- `HOST_STORAGE_PATH` - Path to Archive's storage (must be absolute)
- `ARCHIVE_DB_HOST` - Archive database host (default: db)
- `ARCHIVE_DB_PORT` - Archive database port (default: 5432)
- `ARCHIVE_REDIS_HOST` - Archive Redis host (default: redis)
- `ARCHIVE_REDIS_PORT` - Archive Redis port (default: 6379)
- `FORCE_DB_SETUP` - Force database recreation (default: false)

## Docker Images and Services

### Archive Services
- **archive** (Rails app): `ruby:3.2.5-slim`
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

### Jukebox Services
- **jukebox** (Rails app): `ruby:3.2.5-slim`
  - Ports: 3001 (Rails)
  - Dependencies: Archive's PostgreSQL (db), Redis (redis), Archive app (archive)
  - Volumes: Logs, Archive storage (read-only, absolute path)

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
cd archive && docker compose logs -f

# Jukebox logs
cd jukebox && docker compose logs -f

# Apache2 logs
sudo tail -f /var/log/apache2/archive_error.log
sudo tail -f /var/log/apache2/jukebox_error.log
```

### Updates and restarts
```bash
# Archive update (rebuild image and recreate container)
cd archive
git pull
docker compose up -d --build

# Jukebox update (rebuild image and recreate containers)
cd ../jukebox
git pull
docker compose up -d --build

# Service-specific rebuilds
docker compose build archive && docker compose up -d archive
docker compose build jukebox && docker compose up -d jukebox

# Restart without rebuild (config/env change only)
docker compose restart archive
docker compose restart jukebox

# Force a clean rebuild (ignore cache)
docker compose build --no-cache jukebox && docker compose up -d jukebox
```

### Backup
```bash
# Archive database backup
cd archive
docker compose exec db pg_dump -U postgres archive_production > backup.sql

# Jukebox data backup
cd jukebox
docker compose exec jukebox tar czf jukebox-backup.tar.gz /rails/storage
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
   ```

2. **Archive not running when deploying Jukebox**
   ```bash
   # Check Archive status
   curl -f http://localhost:3000/up
   
   # If Archive is down, start it first
   cd archive && docker compose up -d
   ```

3. **Database connection issues**
   ```bash
   # Check PostgreSQL logs
   cd archive && docker compose logs db
   
   # Verify connection from Jukebox
   cd jukebox && docker compose exec jukebox rails console
   # In console: ActiveRecord::Base.connection.execute("SELECT 1")
   ```

4. **Redis connection issues**
   ```bash
   # Check Redis logs
   cd archive && docker compose logs redis
   
   # Verify connection from Jukebox
   cd jukebox && docker compose exec jukebox rails console
   # In console: Redis.new.ping
   ```

5. **Storage access issues**
   ```bash
   # Check if storage is mounted correctly
   cd jukebox && docker compose exec jukebox ls -la /rails/storage
   
   # Verify Archive storage path
   cd archive && docker compose exec archive ls -la /rails/storage
   ```

6. **Apache2 configuration errors**
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