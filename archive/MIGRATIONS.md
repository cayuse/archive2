# Database Migrations Documentation

This document tracks all database migrations for the Music Archive application.

## Migration Plan

### Phase 1: User Authentication & Authorization
- [x] Create users table with roles (20250714014231_create_users.rb)
- [x] Add authentication fields (email, password_digest, name)
- [x] Add role-based access control
- [x] Install Active Storage (20250714041822_create_active_storage_tables.active_storage.rb)

### Phase 2: Core Music Models
- [x] Create artists table (20250714042206_create_artists.rb)
- [x] Create genres table (20250714042324_create_genres.rb)
- [ ] Create albums table
- [ ] Create songs table
- [ ] Create playlists table

### Phase 3: Relationships & Associations
- [ ] Create join tables for many-to-many relationships
- [ ] Add foreign key constraints
- [ ] Add indexes for performance

### Phase 4: Additional Features
- [ ] Add user playlists (personal collections)
- [ ] Add ratings/reviews system
- [ ] Add metadata fields (release dates, track numbers, etc.)

## Migration Guidelines

1. **Always document the purpose** of each migration
2. **Use meaningful names** for migrations
3. **Include rollback instructions** when complex
4. **Test migrations** in development before production
5. **Consider data integrity** and foreign key constraints
6. **Add appropriate indexes** for performance

## Current Status

No migrations have been created yet. Starting with Phase 1. 