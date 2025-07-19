# Archive Sync Setup and Configuration Guide

This document covers the setup and configuration of the archive synchronization system, including both database sync (Phase 1) and file sync (Phase 2) functionality.

## Table of Contents

1. [Overview](#overview)
2. [System Architecture](#system-architecture)
3. [Phase 1: Database Synchronization](#phase-1-database-synchronization)
4. [Phase 2: File Synchronization](#phase-2-file-synchronization)
5. [Configuration](#configuration)
6. [Deployment](#deployment)
7. [Monitoring and Troubleshooting](#monitoring-and-troubleshooting)

## Overview

The archive sync system enables synchronization between multiple archive nodes in a master-slave architecture. It supports:

- **Database Sync**: Real-time metadata synchronization using PowerSync
- **File Sync**: File synchronization using rsync
- **Standalone Mode**: Independent archive operation
- **Master Mode**: Source of truth that pushes to slaves
- **Slave Mode**: Receives updates from master

## System Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Master        │    │   Slave 1       │    │   Slave 2       │
│   Archive       │    │   Archive       │    │   Archive       │
│                 │    │                 │    │                 │
│ ┌─────────────┐ │    │ ┌─────────────┐ │    │ ┌─────────────┐ │
│ │ PowerSync   │ │    │ │ PowerSync   │ │    │ │ PowerSync   │ │
│ │ (Database)  │ │◄──►│ │ (Database)  │ │    │ │ (Database)  │ │
│ └─────────────┘ │    │ └─────────────┘ │    │ └─────────────┘ │
│                 │    │                 │    │                 │
│ ┌─────────────┐ │    │ ┌─────────────┐ │    │ ┌─────────────┐ │
│ │ rsync       │ │───►│ │ rsync       │ │    │ │ rsync       │ │
│ │ (Files)     │ │    │ │ (Files)     │ │    │ │ (Files)     │ │
│ └─────────────┘ │    │ └─────────────┘ │    │ └─────────────┘ │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Phase 1: Database Synchronization

### Features

- **PowerSync Service**: Background service for database synchronization
- **Role-based Sync**: Master pushes changes, slaves pull changes
- **Status Monitoring**: Real-time sync status and health checks
- **Manual Sync**: Force sync capability for immediate synchronization
- **Error Handling**: Comprehensive error tracking and recovery

### Components

#### PowerSync Service (`app/services/power_sync_service.rb`)

The PowerSync service manages database synchronization:

```ruby
# Start sync service
PowerSyncService.instance.start_sync

# Check sync status
status = PowerSyncService.instance.sync_status

# Force manual sync
PowerSyncService.instance.force_sync
```

#### System Settings (`app/models/system_setting.rb`)

Database settings for sync configuration:

```ruby
# Archive role configuration
SystemSetting.archive_role          # 'standalone', 'master', or 'slave'
SystemSetting.master_archive_url    # Master archive URL (for slaves)
SystemSetting.archive_node_id       # Unique node identifier
SystemSetting.sync_enabled?         # Enable database sync
SystemSetting.sync_interval         # Sync interval in seconds
```

#### Settings UI (`app/views/settings/archive_sync.html.erb`)

Web interface for sync configuration and monitoring:

- Archive role selection
- Master/slave configuration
- Sync status display
- Manual sync controls
- Connection testing

### Database Schema

The sync system uses the `system_settings` table for configuration:

```sql
CREATE TABLE system_settings (
  id SERIAL PRIMARY KEY,
  key VARCHAR(255) UNIQUE NOT NULL,
  value TEXT NOT NULL,
  description TEXT,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);
```

Key settings:
- `archive_role`: Archive role (standalone/master/slave)
- `master_archive_url`: Master archive URL
- `archive_node_id`: Unique node identifier
- `sync_enabled`: Enable database sync
- `sync_interval`: Sync interval in seconds

## Phase 2: File Synchronization

### Features

- **rsync-based Sync**: Efficient file synchronization using rsync
- **Bidirectional Sync**: Master pushes to slaves, slaves pull from master
- **Cron Integration**: Automated sync scheduling
- **Missing File Handling**: Graceful handling during sync operations
- **Status Tracking**: File sync status monitoring

### Components

#### rsync Scripts

**Master to Slave Script** (`scripts/sync_master_to_slaves.sh`):

```bash
#!/bin/bash
# Syncs files from master to all configured slave archives

# Configuration via environment variables:
# ARCHIVE_ROLE=master
# FILE_SYNC_ENABLED=true
# MASTER_STORAGE_PATH=/path/to/storage
# SLAVE_HOSTS="slave1.example.com slave2.example.com"
# SLAVE_STORAGE_PATH=/path/to/storage

rsync -avz --delete \
  --exclude='.git/' \
  --exclude='tmp/' \
  --exclude='log/' \
  "$MASTER_STORAGE_PATH/" "$SLAVE_HOST:$SLAVE_STORAGE_PATH/"
```

**Slave from Master Script** (`scripts/sync_slave_from_master.sh`):

```bash
#!/bin/bash
# Syncs files from master to this slave archive

# Configuration via environment variables:
# ARCHIVE_ROLE=slave
# FILE_SYNC_ENABLED=true
# MASTER_HOST=master.example.com
# MASTER_STORAGE_PATH=/path/to/storage
# LOCAL_STORAGE_PATH=/path/to/storage

rsync -avz --delete \
  --exclude='.git/' \
  --exclude='tmp/' \
  --exclude='log/' \
  "$MASTER_HOST:$MASTER_STORAGE_PATH/" "$LOCAL_STORAGE_PATH/"
```

#### File Sync Settings

Additional system settings for file synchronization:

```ruby
# File sync configuration
SystemSetting.file_sync_enabled?    # Enable file sync
SystemSetting.file_sync_in_progress? # Sync in progress flag
SystemSetting.last_file_sync_time   # Last sync timestamp
SystemSetting.file_sync_status      # Current sync status
SystemSetting.slave_hosts           # Comma-separated slave hosts
SystemSetting.master_host           # Master host for slaves
```

#### Missing File Handling

The Song model includes methods for handling missing files during sync:

```ruby
# Check if audio file is available
song.audio_file_available?

# Get file status
song.audio_file_status  # :not_attached, :syncing, :available, :missing
```

### Cron Integration

Cron job templates are provided in `config/cron/archive_sync.cron`:

```bash
# Master archive: Push files to slaves every 15 minutes
*/15 * * * * cd /path/to/archive && ARCHIVE_ROLE=master FILE_SYNC_ENABLED=true ./scripts/sync_master_to_slaves.sh

# Slave archive: Pull files from master every 10 minutes
*/10 * * * * cd /path/to/archive && ARCHIVE_ROLE=slave FILE_SYNC_ENABLED=true MASTER_HOST=master.example.com ./scripts/sync_slave_from_master.sh
```

## Configuration

### 1. Archive Role Configuration

#### Standalone Mode
```ruby
SystemSetting.set('archive_role', 'standalone', 'Archive role: standalone, master, or slave')
```

#### Master Mode
```ruby
SystemSetting.set('archive_role', 'master', 'Archive role: standalone, master, or slave')
SystemSetting.set('slave_hosts', 'slave1.example.com,slave2.example.com', 'Comma-separated list of slave hosts')
```

#### Slave Mode
```ruby
SystemSetting.set('archive_role', 'slave', 'Archive role: standalone, master, or slave')
SystemSetting.set('master_archive_url', 'http://master.example.com', 'URL of master archive')
SystemSetting.set('master_host', 'master.example.com', 'Master archive host')
```

### 2. Sync Settings

#### Database Sync
```ruby
SystemSetting.set('sync_enabled', true, 'Enable archive-to-archive synchronization')
SystemSetting.set('sync_interval', 300, 'Sync interval in seconds')
```

#### File Sync
```ruby
SystemSetting.set('file_sync_enabled', true, 'Enable file synchronization')
SystemSetting.set('rsync_source_path', '/path/to/storage', 'Source path for rsync')
SystemSetting.set('rsync_dest_path', '/path/to/storage', 'Destination path for rsync')
```

### 3. Web Interface Configuration

Access the sync configuration at `/settings/archive_sync`:

1. **Basic Settings**:
   - Archive Role (standalone/master/slave)
   - Node ID
   - Master Archive URL

2. **Sync Settings**:
   - Enable Database Sync
   - Sync Interval
   - Enable File Sync
   - rsync Paths

3. **File Sync Settings**:
   - Slave Hosts (for master)
   - Master Host (for slaves)

## Deployment

### 1. Prerequisites

- **rsync**: Installed on all archive nodes
- **SSH Keys**: Configured for secure file transfers
- **Network Access**: Between master and slave nodes
- **Storage Paths**: Consistent across all nodes

### 2. SSH Key Setup

#### Generate SSH Keys
```bash
# On master node
ssh-keygen -t rsa -b 4096 -C "archive-sync@master"

# Copy public key to slaves
ssh-copy-id -i ~/.ssh/id_rsa.pub slave1.example.com
ssh-copy-id -i ~/.ssh/id_rsa.pub slave2.example.com
```

#### Test SSH Connectivity
```bash
# Test from master to slaves
ssh slave1.example.com "echo 'SSH connection successful'"
ssh slave2.example.com "echo 'SSH connection successful'"
```

### 3. rsync Script Setup

#### Make Scripts Executable
```bash
chmod +x scripts/sync_master_to_slaves.sh
chmod +x scripts/sync_slave_from_master.sh
```

#### Test Scripts
```bash
# Test master script
ARCHIVE_ROLE=master FILE_SYNC_ENABLED=true ./scripts/sync_master_to_slaves.sh

# Test slave script
ARCHIVE_ROLE=slave FILE_SYNC_ENABLED=true MASTER_HOST=master.example.com ./scripts/sync_slave_from_master.sh
```

### 4. Cron Job Setup

#### Edit Crontab
```bash
crontab -e
```

#### Add Sync Jobs
```bash
# Master archive: Push files to slaves every 15 minutes
*/15 * * * * cd /path/to/archive && ARCHIVE_ROLE=master FILE_SYNC_ENABLED=true ./scripts/sync_master_to_slaves.sh

# Slave archive: Pull files from master every 10 minutes
*/10 * * * * cd /path/to/archive && ARCHIVE_ROLE=slave FILE_SYNC_ENABLED=true MASTER_HOST=master.example.com ./scripts/sync_slave_from_master.sh
```

### 5. PowerSync Service

#### Start Service
```ruby
# In Rails console or application
PowerSyncService.instance.start_sync
```

#### Verify Status
```ruby
status = PowerSyncService.instance.sync_status
puts "Sync running: #{status[:running]}"
puts "Last sync: #{status[:last_sync]}"
puts "File sync status: #{status[:file_sync_status]}"
```

## Monitoring and Troubleshooting

### 1. Sync Status Monitoring

#### Web Interface
- Visit `/settings/archive_sync` for real-time status
- Monitor sync status, error counts, and last sync times
- Use "Force Sync" buttons for manual synchronization

#### Rails Console
```ruby
# Check sync status
status = PowerSyncService.instance.sync_status
puts status

# Check file sync status
puts "File sync enabled: #{SystemSetting.file_sync_enabled?}"
puts "File sync in progress: #{SystemSetting.file_sync_in_progress?}"
puts "Last file sync: #{SystemSetting.last_file_sync_time}"
```

### 2. Log Files

#### rsync Logs
```bash
# Master sync logs
tail -f /tmp/archive_sync_master.log

# Slave sync logs
tail -f /tmp/archive_sync_slave.log
```

#### Rails Logs
```bash
# Application logs
tail -f log/development.log
tail -f log/production.log
```

### 3. Common Issues

#### File Sync Fails
1. **Check SSH connectivity**:
   ```bash
   ssh slave.example.com "echo 'test'"
   ```

2. **Verify rsync paths**:
   ```bash
   ls -la /path/to/storage
   ```

3. **Check permissions**:
   ```bash
   chmod 755 /path/to/storage
   ```

#### Database Sync Issues
1. **Check PowerSync service**:
   ```ruby
   PowerSyncService.instance.sync_status
   ```

2. **Verify settings**:
   ```ruby
   SystemSetting.archive_role
   SystemSetting.sync_enabled?
   ```

3. **Restart service**:
   ```ruby
   PowerSyncService.instance.stop_sync
   PowerSyncService.instance.start_sync
   ```

### 4. Performance Optimization

#### rsync Optimization
- Use `--compress` for slow networks
- Adjust `--bwlimit` for bandwidth control
- Use `--partial` for large files

#### Database Sync Optimization
- Adjust sync interval based on update frequency
- Monitor sync performance in logs
- Use manual sync for large updates

## Security Considerations

### 1. SSH Security
- Use SSH keys instead of passwords
- Restrict SSH access to sync user only
- Use non-standard SSH ports if needed

### 2. Network Security
- Use VPN or private networks for sync traffic
- Firewall rules to restrict access
- Monitor sync traffic for anomalies

### 3. File Permissions
- Restrict file permissions on storage directories
- Use dedicated sync user with minimal privileges
- Regular security audits of sync logs

## Future Enhancements

### Phase 3: Archive-to-Archive API Communication
- REST API endpoints for sync
- Change detection and conflict resolution
- Real-time sync notifications

### Phase 4: Jukebox Multi-Archive Support
- Multiple archive connections
- Failover and load balancing
- Full cache mode for offline operation

### Phase 5: Advanced Features
- Sync compression and encryption
- Bandwidth management
- Advanced conflict resolution
- Sync performance monitoring

---

**Note**: This document covers the current implementation. For the latest updates and additional features, refer to the project documentation and release notes. 