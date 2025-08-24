# Master-Slave Sync Deployment Guide

## Overview

This guide covers the deployment and configuration of the **Archive Master-Slave Sync System**. This system enables multiple Archive instances to synchronize their music databases while maintaining a fail-safe, non-blocking architecture.

**IMPORTANT**: This guide is **supplemental** to the main `DEPLOYMENT_GUIDE.md`. Refer to that guide for general deployment procedures, SSL setup, and basic Archive configuration.

## Architecture

### Master-Slave Sync Pattern
```
┌─────────────────────────────────────────────────────────────────┐
│                        MASTER ARCHIVE                          │
│                    (Public Server)                             │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ • SSL Certificate & Domain                              │   │
│  │ • Static IP / Public Access                             │   │
│  │ • PostgreSQL with UUID Primary Keys                     │   │
│  │ • Slave Key Management                                  │   │
│  │ • Conflict Resolution (Master Wins)                     │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      │ HTTPS API Calls
                      │ (Client Initiated)
                      │
        ┌─────────────┴─────────────┐
        │                           │
        │      CLIENT ARCHIVES      │
        │      (Slave Nodes)        │
        │                           │
        │  ┌─────────────────────┐  │
        │  │ • Behind NAT/Firewall│  │
        │  │ • No Static IP       │  │
        │  │ • No SSL Required    │  │
        │  │ • Configurable Sync  │  │
        │  │   Intervals          │  │
        │  │ • Fail-Safe Operation│  │
        │  └─────────────────────┘  │
        └───────────────────────────┘
```

### Key Features

- **Client-Initiated Sync**: All sync requests originate from slave nodes
- **Fail-Safe Operation**: Sync failures never affect local system performance
- **Configurable Intervals**: Sync frequency adjustable (60s to 1 hour)
- **Master-Wins Conflict Resolution**: UUID-based collision prevention
- **Background Processing**: Sync runs in non-blocking threads
- **Circuit Breaker Protection**: Automatic failure isolation
- **Local Status Tracking**: Sync health monitoring without external calls

## Prerequisites

### Master Archive Requirements
- **Already deployed** Archive instance (refer to `DEPLOYMENT_GUIDE.md`)
- **SSL certificate** and public domain
- **Static IP** or public DNS resolution
- **PostgreSQL database** with UUID primary keys enabled
- **Admin access** to generate slave keys

### Slave Archive Requirements
- **Docker and Docker Compose** (same as master)
- **Network access** to master's HTTPS endpoint
- **Local storage** for music files (separate from sync)
- **Slave key** provided by master administrator

## Master Archive Setup (In-Place Upgrade)

### 1. Database Migration (Safe - Only Adds Tables)

Since your master already has music data, we'll only add the sync tables:

```bash
# Navigate to archive directory
cd archive

# Run migrations (safe - only adds new tables)
docker compose exec archive rails db:migrate

# Verify new tables were created
docker compose exec archive rails db:migrate:status
```

**Expected new tables:**
- `sync_changes` - Tracks database changes for sync
- `slave_keys` - Stores slave authentication keys
- `conflict_logs` - Logs sync conflicts and resolutions
- `sync_status_tracking` - Local sync health monitoring

### 2. Configure Master Role

```bash
# Access the web interface
# Go to: Settings → Archive Sync

# Set Archive Role to: "master"
# Enable Sync: ✓
# Set Sync Interval: 300 (5 minutes - master doesn't use this)
# Save Settings
```

### 3. Generate Slave Keys

For each client archive, generate a unique slave key:

```bash
# In the web interface:
# Settings → Archive Sync → Generate Slave Key

# For each slave:
# 1. Enter descriptive name (e.g., "Home Office Archive")
# 2. Enter node ID (e.g., "home-office-01")
# 3. Click "Generate Key"
# 4. Copy the generated key (displayed only once)
# 5. Provide this key to the slave administrator
```

**Important**: Slave keys are displayed only once. Store them securely and provide them to slave administrators.

### 4. Master Environment Variables

Add these to your master's environment (if using `.env` file or docker-compose):

```bash
# Master Archive Environment
ARCHIVE_ROLE=master
SYNC_ENABLED=true
SYNC_INTERVAL=300
```

## Slave Archive Setup (New Deployment)

### 1. Deploy Archive Instance

Follow the main `DEPLOYMENT_GUIDE.md` for basic Archive deployment, then:

```bash
# Navigate to archive directory
cd archive

# Run migrations
docker compose exec archive rails db:migrate

# Verify sync tables exist
docker compose exec archive rails db:migrate:status
```

### 2. Configure Slave Role

```bash
# Access the web interface
# Go to: Settings → Archive Sync

# Set Archive Role to: "slave"
# Master Archive URL: https://your-master-domain.com
# Archive Node ID: unique-identifier-for-this-node
# Enable Sync: ✓
# Set Sync Interval: 300 (5 minutes - how often to check for updates)
# Save Settings
```

### 3. Store Slave Key

```bash
# In the web interface:
# Settings → Archive Sync → Slave Key Configuration

# Enter the slave key provided by master administrator
# This key is encrypted and stored locally
# Test connection to master
```

### 4. Slave Environment Variables

```bash
# Slave Archive Environment
ARCHIVE_ROLE=slave
SYNC_ENABLED=true
SYNC_INTERVAL=300
MASTER_ARCHIVE_URL=https://your-master-domain.com
```

## Sync Control and Monitoring

### Accessing Sync Control Center

Both master and slave archives have access to:

```
Settings → Archive Sync → Sync Control Center
```

### Master Sync Control Features

- **View all slave connections**
- **Generate/regenerate slave keys**
- **Monitor sync health across all slaves**
- **View conflict logs and resolutions**
- **Emergency stop all sync operations**

### Slave Sync Control Features

- **Pause/resume sync operations**
- **Emergency stop sync**
- **View sync status and health**
- **Configure sync intervals**
- **Monitor local sync attempts**
- **Clear failed sync records**

### Sync Health Indicators

- **Green**: Recent successful syncs
- **Yellow**: Sync paused or delayed
- **Red**: Sync failures or emergency stop
- **Gray**: Sync disabled

## Configuration Options

### Sync Intervals

| Interval | Use Case |
|----------|----------|
| 60s | High-frequency updates (development/testing) |
| 300s | Standard production (5 minutes) |
| 900s | Low-frequency updates (15 minutes) |
| 3600s | Daily sync (1 hour) |

### Timeout Settings

- **Operation Timeout**: Maximum time for any sync operation (10-300s)
- **Connection Timeout**: Network connection timeout (10s)
- **Read Timeout**: API response timeout (20s)

### Circuit Breaker Settings

- **Failure Threshold**: Failures before opening circuit (5)
- **Circuit Timeout**: How long to keep circuit open (5 minutes)
- **Auto-Reset**: Circuit automatically resets after timeout

## Troubleshooting

### Common Issues

#### 1. Slave Cannot Connect to Master

```bash
# Check network connectivity
curl -v https://your-master-domain.com/api/v1/health

# Verify slave key is correct
# Check firewall/NAT settings
# Ensure master domain resolves correctly
```

#### 2. Sync Failing Repeatedly

```bash
# Check sync control center for error messages
# Verify master is accessible
# Check slave key validity
# Review network connectivity
```

#### 3. Database Migration Issues

```bash
# If migrations fail, check PostgreSQL logs
docker compose logs db

# Force migration if needed
docker compose exec archive rails db:migrate:redo

# Check database connection
docker compose exec archive rails db:version
```

### Log Locations

```bash
# Archive application logs
docker compose logs archive

# PostgreSQL logs
docker compose logs db

# Sync-specific logs (in application logs)
# Look for "FailSafeSyncService" entries
```

## Security Considerations

### Master Archive Security

- **HTTPS Required**: All client connections must use HTTPS
- **Slave Key Management**: Rotate keys periodically
- **Access Control**: Limit admin access to sync configuration
- **Network Security**: Use firewalls to restrict access

### Slave Archive Security

- **Local Storage**: Music files stored locally (not synced)
- **Encrypted Keys**: Slave keys encrypted in database
- **No Incoming Ports**: Clients don't need public ports
- **Fail-Safe Operation**: Network issues don't affect local system

## File Sync (Separate from Database Sync)

**Note**: This guide focuses on database synchronization. Music file synchronization requires a separate rsync process that will be documented separately.

The current sync system handles:
- ✅ **Database changes** (songs, artists, albums, playlists, etc.)
- ✅ **Metadata updates**
- ✅ **User data**
- ✅ **Configuration changes**

**Not handled by current sync:**
- ❌ **Music files** (MP3, FLAC, etc.)
- ❌ **Large binary data**
- ❌ **File storage synchronization**

## Recovery and Maintenance

### If Master Crashes

1. **Restore master from backup**
2. **Verify sync tables exist**
3. **Regenerate slave keys if needed**
4. **Slaves will automatically reconnect**

### If Slave Crashes

1. **Restore slave from backup**
2. **Re-enter master URL and slave key**
3. **Perform initial sync to catch up**
4. **Monitor sync health**

### Database Backup Strategy

```bash
# Master backup (includes all data)
docker compose exec db pg_dump -U postgres archive_production > master_backup.sql

# Slave backup (local data only)
docker compose exec db pg_dump -U postgres archive_production > slave_backup.sql
```

## Performance Considerations

### Master Archive

- **Sync operations are lightweight** (API calls only)
- **No background sync processing** (waits for client requests)
- **Minimal performance impact** from sync operations

### Slave Archive

- **Sync runs in background threads** (non-blocking)
- **Configurable sync frequency** (adjust based on needs)
- **Local status tracking** (no external calls for health checks)
- **Fail-fast operation** (network issues don't slow system)

## Next Steps

After implementing this sync system:

1. **Test sync operations** between master and slave
2. **Monitor sync health** for first few days
3. **Adjust sync intervals** based on usage patterns
4. **Implement file sync** (rsync process) for music files
5. **Set up monitoring** and alerting for sync failures

## Support and Debugging

### Getting Help

If you encounter issues:

1. **Check sync control center** for error messages
2. **Review application logs** for detailed error information
3. **Verify network connectivity** between master and slaves
4. **Check database migration status** on both systems

### Debug Mode

Enable debug logging for sync operations:

```bash
# Add to environment
RAILS_LOG_LEVEL=debug

# Restart archive container
docker compose restart archive
```

---

**Remember**: This sync system is designed to be **fail-safe** and **non-blocking**. If sync fails, your local Archive system continues to function normally. Sync can always be resumed manually through the control center.
