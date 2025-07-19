# Archive Sync Quick Reference

Quick reference for common archive sync operations and troubleshooting.

## Quick Setup

### 1. Enable Archive Sync
```ruby
# In Rails console
SystemSetting.set('archive_role', 'master', 'Archive role')
SystemSetting.set('sync_enabled', 'true', 'Enable sync')
SystemSetting.set('file_sync_enabled', 'true', 'Enable file sync')
```

### 2. Start PowerSync Service
```ruby
PowerSyncService.instance.start_sync
```

### 3. Check Status
```ruby
status = PowerSyncService.instance.sync_status
puts status
```

## Common Commands

### Database Sync
```ruby
# Force database sync
PowerSyncService.instance.force_sync

# Check sync status
PowerSyncService.instance.sync_status

# Start/stop service
PowerSyncService.instance.start_sync
PowerSyncService.instance.stop_sync
```

### File Sync
```ruby
# Force file sync
PowerSyncService.instance.force_file_sync

# Check file sync status
SystemSetting.file_sync_enabled?
SystemSetting.file_sync_in_progress?
SystemSetting.last_file_sync_time
```

### Manual rsync
```bash
# Master to slaves
ARCHIVE_ROLE=master FILE_SYNC_ENABLED=true ./scripts/sync_master_to_slaves.sh

# Slave from master
ARCHIVE_ROLE=slave FILE_SYNC_ENABLED=true MASTER_HOST=master.example.com ./scripts/sync_slave_from_master.sh
```

## Configuration

### Archive Roles
```ruby
# Standalone
SystemSetting.set('archive_role', 'standalone')

# Master
SystemSetting.set('archive_role', 'master')
SystemSetting.set('slave_hosts', 'slave1.example.com,slave2.example.com')

# Slave
SystemSetting.set('archive_role', 'slave')
SystemSetting.set('master_archive_url', 'http://master.example.com')
SystemSetting.set('master_host', 'master.example.com')
```

### Sync Settings
```ruby
# Database sync
SystemSetting.set('sync_enabled', 'true')
SystemSetting.set('sync_interval', '300')  # 5 minutes

# File sync
SystemSetting.set('file_sync_enabled', 'true')
SystemSetting.set('rsync_source_path', '/path/to/storage')
SystemSetting.set('rsync_dest_path', '/path/to/storage')
```

## Monitoring

### Web Interface
- **URL**: `/settings/archive_sync`
- **Features**: Status monitoring, manual sync, configuration

### Log Files
```bash
# rsync logs
tail -f /tmp/archive_sync_master.log
tail -f /tmp/archive_sync_slave.log

# Rails logs
tail -f log/development.log
```

### Status Check
```ruby
# Full status
status = PowerSyncService.instance.sync_status
puts "Running: #{status[:running]}"
puts "Last sync: #{status[:last_sync]}"
puts "File sync: #{status[:file_sync_status]}"

# Health check
PowerSyncService.instance.healthy?
```

## Troubleshooting

### File Sync Issues
```bash
# Test SSH connectivity
ssh slave.example.com "echo 'test'"

# Check rsync paths
ls -la /path/to/storage

# Test rsync manually
rsync -avz --dry-run /source/ /dest/
```

### Database Sync Issues
```ruby
# Check service status
PowerSyncService.instance.sync_status

# Restart service
PowerSyncService.instance.stop_sync
sleep 1
PowerSyncService.instance.start_sync

# Check settings
SystemSetting.archive_role
SystemSetting.sync_enabled?
```

### Missing Files
```ruby
# Check file availability
song.audio_file_available?
song.audio_file_status

# Check sync status
SystemSetting.file_sync_in_progress?
```

## Cron Jobs

### Master Archive
```bash
# Push to slaves every 15 minutes
*/15 * * * * cd /path/to/archive && ARCHIVE_ROLE=master FILE_SYNC_ENABLED=true ./scripts/sync_master_to_slaves.sh
```

### Slave Archive
```bash
# Pull from master every 10 minutes
*/10 * * * * cd /path/to/archive && ARCHIVE_ROLE=slave FILE_SYNC_ENABLED=true MASTER_HOST=master.example.com ./scripts/sync_slave_from_master.sh
```

## Environment Variables

### Master Script
```bash
ARCHIVE_ROLE=master
FILE_SYNC_ENABLED=true
MASTER_STORAGE_PATH=/path/to/storage
SLAVE_HOSTS="slave1.example.com slave2.example.com"
SLAVE_STORAGE_PATH=/path/to/storage
SSH_USER=vscode
```

### Slave Script
```bash
ARCHIVE_ROLE=slave
FILE_SYNC_ENABLED=true
MASTER_HOST=master.example.com
MASTER_STORAGE_PATH=/path/to/storage
LOCAL_STORAGE_PATH=/path/to/storage
SSH_USER=vscode
```

## File Status Codes

### Audio File Status
- `:not_attached` - No audio file attached
- `:syncing` - File is being synced from master
- `:available` - File is available locally
- `:missing` - File not found locally

### Sync Status
- `idle` - No sync in progress
- `syncing` - Sync currently running
- `completed` - Last sync completed successfully
- `failed` - Last sync failed

## Security Checklist

- [ ] SSH keys configured
- [ ] SSH connectivity tested
- [ ] File permissions set correctly
- [ ] Network access configured
- [ ] Firewall rules updated
- [ ] Sync user has minimal privileges

## Performance Tips

- Use `--compress` for slow networks
- Adjust sync intervals based on update frequency
- Monitor log files for performance issues
- Use manual sync for large updates
- Consider bandwidth limits for rsync

---

**For detailed documentation, see `ARCHIVE_SYNC_SETUP.md`** 