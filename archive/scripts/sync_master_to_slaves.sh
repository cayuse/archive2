#!/bin/bash

# Master to Slave File Sync Script
# This script syncs files from master archive to all configured slave archives

set -e

# Configuration - these will be read from system settings in production
MASTER_STORAGE_PATH="${MASTER_STORAGE_PATH:-/workspaces/dockercrap/archive/storage}"
SLAVE_HOSTS=(${SLAVE_HOSTS:-"localhost"})
SLAVE_STORAGE_PATH="${SLAVE_STORAGE_PATH:-/workspaces/dockercrap/archive/storage}"
SSH_USER="${SSH_USER:-vscode}"

# Logging
LOG_FILE="/tmp/archive_sync_master.log"
echo "$(date): Starting master to slave file sync" >> "$LOG_FILE"

# Check if we're configured as master
if [ "$ARCHIVE_ROLE" != "master" ]; then
    echo "$(date): Not configured as master, skipping sync" >> "$LOG_FILE"
    exit 0
fi

# Check if file sync is enabled
if [ "$FILE_SYNC_ENABLED" != "true" ]; then
    echo "$(date): File sync disabled, skipping" >> "$LOG_FILE"
    exit 0
fi

# Sync to each slave
for slave_host in "${SLAVE_HOSTS[@]}"; do
    echo "$(date): Syncing to slave: $slave_host" >> "$LOG_FILE"
    
    # Use rsync to sync files
    if [ "$slave_host" = "localhost" ]; then
        # Local sync (for testing)
        rsync -avz --delete \
            --exclude='.git/' \
            --exclude='tmp/' \
            --exclude='log/' \
            "$MASTER_STORAGE_PATH/" "$SLAVE_STORAGE_PATH/" 2>> "$LOG_FILE"
    else
        # Remote sync
        rsync -avz --delete \
            --exclude='.git/' \
            --exclude='tmp/' \
            --exclude='log/' \
            -e "ssh -o StrictHostKeyChecking=no" \
            "$MASTER_STORAGE_PATH/" "$SSH_USER@$slave_host:$SLAVE_STORAGE_PATH/" 2>> "$LOG_FILE"
    fi
    
    if [ $? -eq 0 ]; then
        echo "$(date): Successfully synced to $slave_host" >> "$LOG_FILE"
    else
        echo "$(date): Failed to sync to $slave_host" >> "$LOG_FILE"
        exit 1
    fi
done

echo "$(date): Master to slave file sync completed" >> "$LOG_FILE"
exit 0 