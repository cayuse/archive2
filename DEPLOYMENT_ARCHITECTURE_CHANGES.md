# Deployment Architecture Changes

## Overview

This document outlines the changes made to the deployment system to support the new shared architecture where Jukebox depends on Archive's services rather than running standalone.

## Key Changes Made

### 1. Archive Deployment (`archive/deploy.sh`)

**Added configurable paths:**
- `HOST_STORAGE_PATH` - Configurable music storage directory
- `POSTGRES_DATA_PATH` - Configurable PostgreSQL data directory
- Automatic directory creation if paths don't exist

**Updated docker-compose.yml:**
- Created standalone `archive/docker-compose.yml` (was using root-level)
- Added configurable volume mounts for storage and database
- Includes Redis, PostgreSQL, Archive Rails app, and Sidekiq worker

**Updated Dockerfile:**
- Added `ffmpeg` package for audio processing

### 2. Jukebox Deployment (`jukebox/deploy.sh`)

**Added dependency checking:**
- Verifies Archive is running before deployment
- Sets up connection to Archive's services automatically
- Configures shared database, Redis, and storage paths

**Environment variables:**
- `ARCHIVE_DB_HOST`, `ARCHIVE_DB_PORT` - Database connection
- `ARCHIVE_REDIS_HOST`, `ARCHIVE_REDIS_PORT` - Redis connection  
- `ARCHIVE_STORAGE_PATH` - Storage directory path
- `POSTGRES_PASSWORD` - Must match Archive's password

### 3. Jukebox Docker Services (`jukebox/docker-compose.yml`)

**Removed standalone services:**
- No more local Redis (uses Archive's)
- No more local database (uses Archive's)

**Added new services:**
- **MPD** - Music Player Daemon for audio playback
- **jukebox-player** - Python controller for MPD and queue management

**Updated Jukebox Rails app:**
- Connects to Archive's PostgreSQL database
- Connects to Archive's Redis instance
- Mounts Archive's storage in read-only mode

### 4. Python Player Container (`jukebox/audio_player/Dockerfile`)

**New container:**
- Based on `python:3.11-slim`
- Includes MPD client tools and Redis tools
- Runs the Python player script in containerized environment

### 5. Documentation Updates (`DEPLOYMENT_GUIDE.md`)

**Architecture changes:**
- Updated to reflect shared services model
- Added deployment order requirements
- Documented new environment variables
- Added troubleshooting for shared services

**New sections:**
- Deployment Order and Dependencies
- Storage Configuration
- Service descriptions for all containers
- Enhanced troubleshooting guide

## Deployment Order

1. **Archive First** - Must be running before Jukebox
2. **Jukebox Second** - Depends on Archive's services

## Environment Variables

### Archive Required
- `RAILS_MASTER_KEY`

### Archive Optional  
- `POSTGRES_PASSWORD` (default: password)
- `HOST_STORAGE_PATH` (default: ./storage)
- `POSTGRES_DATA_PATH` (default: ./postgres_data)

### Jukebox Required
- `RAILS_MASTER_KEY`
- `POSTGRES_PASSWORD` (must match Archive)

### Jukebox Optional
- `ARCHIVE_SERVER_URL` (default: http://localhost:3000)
- `ARCHIVE_DB_HOST` (default: localhost)
- `ARCHIVE_DB_PORT` (default: 5432)
- `ARCHIVE_REDIS_HOST` (default: localhost)
- `ARCHIVE_REDIS_PORT` (default: 6379)
- `ARCHIVE_STORAGE_PATH` (default: ../archive/storage)

## Service Architecture

```
Archive (Port 3000)
├── PostgreSQL (Port 5432)
├── Redis (Port 6379)
└── Storage (Configurable path)

Jukebox (Port 3001)
├── MPD (Port 6600)
├── Python Player
└── Rails App (connects to Archive services)
```

## Benefits of New Architecture

1. **No Duplication** - Single database, Redis, and storage
2. **Consistency** - Both apps see the same data
3. **Easier Management** - Single source of truth for music files
4. **Resource Efficiency** - No duplicate services running
5. **Simplified Backup** - One database and storage to backup

## Migration Notes

- **Existing deployments** need to be updated to new architecture
- **Data migration** may be required if moving from standalone setup
- **Storage paths** should be configured for production use
- **Environment variables** must be set correctly for shared services

## Testing the New Setup

1. Deploy Archive and verify it's running
2. Deploy Jukebox and check service connections
3. Verify MPD can access music files
4. Test Python player communication with MPD and Jukebox API
5. Check that both apps can access shared data
