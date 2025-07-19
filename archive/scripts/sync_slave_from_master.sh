#!/bin/bash

# Slave from Master File Sync Script
# This script syncs files from master archive to this slave archive

set -e

# Configuration - these will be read from system settings in production
MASTER_HOST="${MASTER_HOST:-localhost}"
MASTER_STORAGE_PATH="${MASTER_STORAGE_PATH:-/workspaces/dockercrap/archive/storage}"
LOCAL_STORAGE_PATH="${LOCAL_STORAGE_PATH:-/workspaces/dockercrap/archive/storage}"
SSH_USER="${SSH_USER:-vscode}"

# Logging
LOG_FILE="/tmp/archive_sync_slave.log"
echo "$(date): Starting slave from master file sync" >> "$LOG_FILE"

# Check if we're configured as slave
if [ "$ARCHIVE_ROLE" != "slave" ]; then
    echo "$(date): Not configured as slave, skipping sync" >> "$LOG_FILE"
    exit 0
fi

# Check if file sync is enabled
if [ "$FILE_SYNC_ENABLED" != "true" ]; then
    echo "$(date): File sync disabled, skipping" >> "$LOG_FILE"
    exit 0
fi

# Check if master host is configured
if [ -z "$MASTER_HOST" ]; then
    echo "$(date): No master host configured, skipping sync" >> "$LOG_FILE"
    exit 0
fi

echo "$(date): Syncing from master: $MASTER_HOST" >> "$LOG_FILE"

# Use rsync to sync files from master
if [ "$MASTER_HOST" = "localhost" ]; then
    # Local sync (for testing)
    rsync -avz --delete \
        --exclude='.git/' \
        --exclude='tmp/' \
        --exclude='log/' \
        "$MASTER_STORAGE_PATH/" "$LOCAL_STORAGE_PATH/" 2>> "$LOG_FILE"
else
    # Remote sync
    rsync -avz --delete \
        --exclude='.git/' \
        --exclude='tmp/' \
        --exclude='log/' \
        -e "ssh -o StrictHostKeyChecking=no" \
        "$SSH_USER@$MASTER_HOST:$MASTER_STORAGE_PATH/" "$LOCAL_STORAGE_PATH/" 2>> "$LOG_FILE"
fi

if [ $? -eq 0 ]; then
    echo "$(date): Successfully synced from master" >> "$LOG_FILE"
    exit 0
else
    echo "$(date): Failed to sync from master" >> "$LOG_FILE"
    exit 1
fi 