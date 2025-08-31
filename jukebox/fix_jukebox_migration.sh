#!/bin/bash
# Fix Jukebox Migration Issues
# Run this if jukebox migrations fail due to duplicate system_settings

set -e

echo "🔧 Fixing Jukebox Migration Issues"
echo "=================================="

# Check if we're in the jukebox directory
if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Error: Run this script from the jukebox directory"
    exit 1
fi

echo "📋 Current migration status:"
docker compose exec -T jukebox bash -lc './bin/rails db:migrate:status' || echo "Could not get migration status"

echo ""
echo "🧹 Cleaning up duplicate system_settings entries..."
docker compose exec -T jukebox bash -lc './bin/rails runner "
# Remove duplicate system_settings entries, keeping the first one
duplicates = SystemSetting.select(:key).group(:key).having(\"count(*) > 1\").pluck(:key)
puts \"Found #{duplicates.length} duplicate keys: #{duplicates.join(\", \")}\"

duplicates.each do |key|
  records = SystemSetting.where(key: key).order(:id)
  keep = records.first
  remove = records[1..-1]
  puts \"Keeping #{keep.id} (#{key}), removing #{remove.map(&:id).join(\", \")}\"
  remove.each(&:destroy!)
end

puts \"Cleanup complete\"
"' || echo "❌ Failed to clean up duplicates"

echo ""
echo "🔄 Resetting migration state and retrying..."
# Reset the failed migration
docker compose exec -T jukebox bash -lc './bin/rails db:migrate:down VERSION=20250719181733' 2>/dev/null || echo "Migration not in 'up' state"

echo ""
echo "🚀 Running migrations again..."
if docker compose exec -T jukebox bash -lc './bin/rails db:migrate'; then
    echo "✅ Migrations completed successfully!"
else
    echo "❌ Migrations still failing. Check the error above."
    echo ""
    echo "📋 Final migration status:"
    docker compose exec -T jukebox bash -lc './bin/rails db:migrate:status' || echo "Could not get migration status"
    exit 1
fi

echo ""
echo "✅ Jukebox migration fix complete!"
echo ""
echo "🧪 Testing if jukebox tables now exist..."
docker compose exec -T jukebox bash -lc './bin/rails runner "
tables = %w[jukebox_playlists jukebox_playlist_songs jukebox_queue_items jukebox_cached_songs jukebox_played_songs system_settings]
tables.each do |table|
  exists = ActiveRecord::Base.connection.table_exists?(table)
  puts \"#{exists ? \"✅\" : \"❌\"} #{table}\"
end
"' || echo "Could not verify tables"

echo ""
echo "🎵 You can now restart the jukebox service:"
echo "   docker compose restart jukebox"
