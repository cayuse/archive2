# Deployment Guide

## Overview

This system consists of two independent applications that can be deployed separately:

1. **Archive** - Central music repository with PostgreSQL
2. **Jukebox** - Local music player with Redis and SQLite

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
    │  │ Jukebox │ │  Redis  │  │
    │  │ :3001   │ │ :6379   │  │
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

## Deployment Options

### Option 1: Deploy Archive Only
```bash
cd archive
export RAILS_MASTER_KEY=your_master_key_here
export POSTGRES_PASSWORD=your_secure_password
./deploy.sh
```

### Option 2: Deploy Jukebox Only
```bash
cd jukebox
export RAILS_MASTER_KEY=your_master_key_here
export ARCHIVE_SERVER_URL=http://your-archive-server.com
./deploy.sh
```

### Option 3: Deploy Both on Same Server
```bash
# Deploy Archive first
cd archive
export RAILS_MASTER_KEY=your_master_key_here
./deploy.sh

# Deploy Jukebox second
cd ../jukebox
export RAILS_MASTER_KEY=your_master_key_here
export ARCHIVE_SERVER_URL=http://localhost:3000
./deploy.sh
```

## Environment Variables

### Archive Required
- `RAILS_MASTER_KEY` - Rails master key for credentials

### Archive Optional
- `POSTGRES_PASSWORD` - PostgreSQL password (default: password)

### Jukebox Required
- `RAILS_MASTER_KEY` - Rails master key for credentials

### Jukebox Optional
- `ARCHIVE_SERVER_URL` - URL of Archive server (default: http://localhost:3000)
- `JUKEBOX_CLIENT_ID` - Unique client identifier (default: jukebox-1)

## Docker Images

### Archive
- **Base**: `ghcr.io/rails/devcontainer/images/ruby:3.3.8`
- **Database**: `postgres:15`
- **Ports**: 3000 (Rails), 5432 (PostgreSQL)

### Jukebox
- **Base**: `ruby:3.3.8-slim`
- **Cache**: `redis:7-alpine`
- **Ports**: 3001 (Rails), 6379 (Redis)

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
   ```

2. **Database connection issues**
   ```bash
   # Check PostgreSQL logs
   cd archive && docker-compose logs db
   ```

3. **Redis connection issues**
   ```bash
   # Check Redis logs
   cd jukebox && docker-compose logs redis
   ```

4. **Apache2 configuration errors**
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