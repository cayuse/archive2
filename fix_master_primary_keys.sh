#!/bin/bash

# Fix Primary Keys for PostgreSQL Logical Replication
# Run this script on the MASTER server to add missing primary keys
# Required for logical replication DELETE operations

set -e

echo "🔧 Fixing Primary Keys for PostgreSQL Logical Replication"
echo "========================================================="
echo ""

# Check if we're in the correct directory
if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Error: docker-compose.yml not found"
    echo "Please run this script from the archive directory containing docker-compose.yml"
    exit 1
fi

echo "📋 Adding missing primary keys to junction tables..."

# Fix albums_genres table
echo "  - Adding primary key to albums_genres..."
docker compose exec db psql -U postgres -d archive_production -c "
    ALTER TABLE albums_genres ADD CONSTRAINT albums_genres_pkey PRIMARY KEY (album_id, genre_id);
" 2>/dev/null && echo "    ✅ albums_genres primary key added" || echo "    ⚠️  albums_genres primary key may already exist"

# Fix artists_genres table  
echo "  - Adding primary key to artists_genres..."
docker compose exec db psql -U postgres -d archive_production -c "
    ALTER TABLE artists_genres ADD CONSTRAINT artists_genres_pkey PRIMARY KEY (artist_id, genre_id);
" 2>/dev/null && echo "    ✅ artists_genres primary key added" || echo "    ⚠️  artists_genres primary key may already exist"

# Fix playlists_songs table
echo "  - Adding primary key to playlists_songs..."
docker compose exec db psql -U postgres -d archive_production -c "
    ALTER TABLE playlists_songs ADD CONSTRAINT playlists_songs_pkey PRIMARY KEY (playlist_id, song_id);
" 2>/dev/null && echo "    ✅ playlists_songs primary key added" || echo "    ⚠️  playlists_songs primary key may already exist"

echo ""
echo "🔍 Verifying all publication tables have primary keys..."

# Verify all tables now have primary keys
docker compose exec db psql -U postgres -d archive_production -c "
SELECT 
  t.tablename,
  CASE WHEN pk.constraint_name IS NULL THEN '❌ NO PRIMARY KEY' ELSE '✅ HAS PRIMARY KEY' END as pk_status
FROM pg_tables t
LEFT JOIN information_schema.table_constraints pk ON t.tablename = pk.table_name AND pk.constraint_type = 'PRIMARY KEY'
WHERE t.schemaname = 'public' 
  AND t.tablename IN (
    'active_storage_attachments', 'active_storage_blobs', 'active_storage_variant_records',
    'albums', 'albums_genres', 'artists', 'artists_genres', 'genres',
    'playlists', 'playlists_songs', 'songs', 'system_settings', 'theme_assets',
    'themes', 'users'
  )
ORDER BY t.tablename;
"

echo ""
echo "✨ Primary key fixes complete!"
echo ""
echo "📝 What was fixed:"
echo "  - albums_genres: Added composite primary key (album_id, genre_id)"
echo "  - artists_genres: Added composite primary key (artist_id, genre_id)" 
echo "  - playlists_songs: Added composite primary key (playlist_id, song_id)"
echo ""
echo "🎯 Result: DELETE operations should now work properly with logical replication"
echo "   You can now delete songs, and the deletions will replicate to slaves correctly."
