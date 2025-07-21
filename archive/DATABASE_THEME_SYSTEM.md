# Database-Driven Theme System

## Overview

The new database-driven theme system replaces the filesystem-based approach with a fully database-stored solution that integrates with PowerSync for real-time propagation between archive instances. This allows themes to be created, modified, and distributed across multiple archives automatically.

## Architecture

### Database Schema

```sql
-- Themes table
CREATE TABLE themes (
  id SERIAL PRIMARY KEY,
  name VARCHAR NOT NULL UNIQUE,
  display_name VARCHAR NOT NULL,
  description TEXT,
  is_default BOOLEAN DEFAULT FALSE,
  is_active BOOLEAN DEFAULT TRUE,
  css_variables JSONB DEFAULT '{}',
  custom_css TEXT,
  version VARCHAR DEFAULT '1.0.0',
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);

-- Theme assets table
CREATE TABLE theme_assets (
  id SERIAL PRIMARY KEY,
  theme_id INTEGER REFERENCES themes(id) ON DELETE CASCADE,
  asset_type VARCHAR NOT NULL, -- 'icon', 'image', 'logo', 'css'
  filename VARCHAR NOT NULL,
  content_type VARCHAR NOT NULL,
  file_data BYTEA NOT NULL,
  file_size INTEGER NOT NULL,
  checksum VARCHAR NOT NULL,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMP,
  updated_at TIMESTAMP,
  UNIQUE(theme_id, asset_type, filename)
);
```

### PowerSync Integration

Themes and theme assets are automatically included in PowerSync synchronization:

- **Master Archives**: Theme changes are pushed to all slave archives
- **Slave Archives**: Theme changes are pulled from master archives
- **Real-time Updates**: Theme modifications propagate immediately
- **Conflict Resolution**: Server-wins for theme conflicts

## Features

### 1. Database Storage
- **CSS Variables**: Stored as JSONB for easy querying and modification
- **Custom CSS**: Full CSS support with syntax highlighting
- **Binary Assets**: Icons, images, and logos stored as binary data
- **Metadata**: Rich metadata for assets (dimensions, tags, etc.)

### 2. Asset Management
- **Multiple Asset Types**: Icons, images, logos, CSS files
- **File Validation**: Content type and size validation
- **Checksum Verification**: Ensures asset integrity
- **Duplicate Prevention**: Unique constraints prevent duplicates

### 3. Theme Operations
- **Import/Export**: Bidirectional filesystem integration
- **Duplication**: Easy theme copying and modification
- **Versioning**: Theme version tracking
- **Activation/Deactivation**: Enable/disable themes

### 4. PowerSync Propagation
- **Automatic Sync**: Theme changes trigger immediate sync
- **Asset Synchronization**: Binary assets sync between archives
- **Conflict Handling**: Server-wins resolution for theme conflicts
- **Performance**: Optimized for large asset transfers

## Usage

### Theme Management

#### Creating a New Theme
```ruby
# Create theme with CSS variables
theme = Theme.create!(
  name: 'my-theme',
  display_name: 'My Custom Theme',
  description: 'A beautiful custom theme',
  css_variables: {
    'primary-bg' => '#1a1a2e',
    'accent-color' => '#4f46e5',
    'text-primary' => '#f8fafc'
  },
  custom_css: <<~CSS
    [data-theme="my-theme"] .card {
      border-radius: 1rem;
      box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
    }
  CSS
)

# Add assets to theme
theme.theme_assets.create!(
  asset_type: 'logo',
  filename: 'logo.svg',
  content_type: 'image/svg+xml',
  file_data: File.binread('path/to/logo.svg'),
  file_size: File.size('path/to/logo.svg'),
  checksum: Digest::SHA256.hexdigest(File.binread('path/to/logo.svg'))
)
```

#### Importing from Filesystem
```ruby
# Import existing filesystem theme
theme = Theme.new(name: 'existing-theme')
theme.import_from_filesystem('existing-theme')
theme.save!
```

#### Exporting to Filesystem
```ruby
# Export theme to filesystem
theme.export_to_filesystem
```

### Asset Management

#### Adding Assets
```ruby
# Add icon
theme.theme_assets.create!(
  asset_type: 'icon',
  filename: 'play.svg',
  content_type: 'image/svg+xml',
  file_data: svg_content,
  file_size: svg_content.bytesize,
  checksum: Digest::SHA256.hexdigest(svg_content)
)

# Add image
theme.theme_assets.create!(
  asset_type: 'image',
  filename: 'background.jpg',
  content_type: 'image/jpeg',
  file_data: image_data,
  file_size: image_data.bytesize,
  checksum: Digest::SHA256.hexdigest(image_data)
)
```

#### Retrieving Assets
```ruby
# Get theme asset URL
icon_url = theme.icon_url('play.svg')
image_url = theme.image_url('background.jpg')
logo_url = theme.logo_url

# Get asset data
asset = theme.asset_by_type_and_filename('icon', 'play.svg')
asset_data = asset.file_data
```

### View Integration

#### Theme Helpers
```erb
<!-- Display theme icon -->
<%= theme_icon_tag('play.svg', width: 32, height: 32) %>

<!-- Display theme image -->
<%= theme_image_tag('background.jpg', class: 'img-fluid') %>

<!-- Get theme asset paths -->
<img src="<%= theme_logo_path %>" alt="Logo">
<img src="<%= theme_icon_path('play.svg') %>" alt="Play">
```

#### CSS Integration
```erb
<!-- Include theme CSS -->
<%= stylesheet_link_tag theme_css_path, "data-theme": current_theme_name %>
```

## Migration from Filesystem

### Automatic Migration
```ruby
# Migrate all existing themes
result = ThemeMigrationService.migrate_all_themes

puts "Migrated #{result[:successful_migrations]} themes"
puts "Errors: #{result[:errors].length}"

# Create default theme if none exists
ThemeMigrationService.create_default_theme

# Validate migration
validation = ThemeMigrationService.validate_migration
puts "All themes migrated: #{validation[:all_migrated]}"
```

### Manual Migration
```ruby
# Migrate specific theme
theme = ThemeMigrationService.migrate_theme('christmas')

# Clean up filesystem themes (optional)
ThemeMigrationService.cleanup_filesystem_themes
```

## PowerSync Configuration

### Theme Tables in PowerSync
```ruby
# In PowerSync configuration
config.sync_tables = [
  :songs, :artists, :albums, :genres, :playlists,
  :themes, :theme_assets  # Add theme tables
]

config.access_control = {
  jukebox: {
    read: [:songs, :artists, :albums, :genres, :playlists, :themes, :theme_assets],
    write: []
  }
}
```

### Theme Change Notifications
```ruby
# Theme changes automatically trigger sync
theme.update!(css_variables: new_variables)
# PowerSync automatically syncs to slaves

asset.update_file_data(new_data)
# PowerSync automatically syncs to slaves
```

## API Endpoints

### Theme Assets
```
GET /themes/:theme.css
GET /themes/:theme/assets/:asset_type/:filename
```

### Theme Management (Admin)
```
GET    /themes
POST   /themes
GET    /themes/:id/edit
PATCH  /themes/:id
DELETE /themes/:id
POST   /themes/:id/import
POST   /themes/:id/export
POST   /themes/:id/duplicate
```

## Performance Considerations

### Asset Optimization
- **Caching**: Assets are cached with ETags for 24 hours
- **Compression**: Binary assets are served with appropriate compression
- **CDN Ready**: Asset URLs work with CDNs
- **Lazy Loading**: Assets load on-demand

### Database Optimization
- **Indexing**: Proper indexes on theme and asset queries
- **Binary Storage**: Efficient binary data storage
- **JSONB Queries**: Fast CSS variable queries
- **Connection Pooling**: Optimized for concurrent access

### Sync Performance
- **Incremental Sync**: Only changed assets are synced
- **Batch Processing**: Large asset transfers are batched
- **Background Processing**: Sync operations don't block UI
- **Error Recovery**: Failed syncs are retried automatically

## Security

### Access Control
- **Admin Only**: Theme management requires admin privileges
- **Public Assets**: Theme assets are publicly accessible
- **Input Validation**: All theme data is validated
- **File Type Restrictions**: Only allowed file types are accepted

### Data Integrity
- **Checksums**: All assets have SHA256 checksums
- **Validation**: File content is validated on upload
- **Backup**: Theme data is included in database backups
- **Versioning**: Theme versions are tracked

## Troubleshooting

### Common Issues

#### Theme Not Loading
```ruby
# Check if theme exists
theme = Theme.find_by(name: 'theme-name')
puts "Theme exists: #{theme.present?}"

# Check if theme is active
puts "Theme active: #{theme&.is_active?}"

# Check theme assets
puts "Theme assets: #{theme&.theme_assets&.count}"
```

#### Asset Not Found
```ruby
# Check if asset exists
asset = theme.asset_by_type_and_filename('icon', 'play.svg')
puts "Asset exists: #{asset.present?}"

# Check asset URL
puts "Asset URL: #{theme.icon_url('play.svg')}"
```

#### Sync Issues
```ruby
# Check sync status
status = PowerSyncService.instance.sync_status
puts "Sync healthy: #{PowerSyncService.instance.healthy?}"

# Force sync
PowerSyncService.instance.force_sync
```

### Debugging

#### Theme Debugging
```ruby
# Debug theme CSS
puts theme.full_css

# Debug CSS variables
puts theme.css_variables_css

# Debug asset URLs
theme.theme_assets.each do |asset|
  puts "#{asset.asset_type}/#{asset.filename}: #{asset.url}"
end
```

#### Sync Debugging
```ruby
# Check theme changes
changes = PowerSyncService.instance.get_theme_changes_since(1.hour.ago)
puts "Theme changes: #{changes.length}"

# Check asset changes
changes = PowerSyncService.instance.get_theme_asset_changes_since(1.hour.ago)
puts "Asset changes: #{changes.length}"
```

## Future Enhancements

### Planned Features
- **Theme Templates**: Pre-built theme templates
- **Theme Marketplace**: Share themes between archives
- **Advanced CSS Editor**: Visual CSS editor
- **Theme Analytics**: Usage statistics
- **A/B Testing**: Theme testing framework
- **Mobile Themes**: Responsive theme variants

### Performance Improvements
- **Asset Compression**: Automatic image optimization
- **CDN Integration**: Direct CDN upload
- **Caching Layers**: Multi-level caching
- **Background Processing**: Async asset processing

## Conclusion

The database-driven theme system provides a robust, scalable solution for theme management across multiple archive instances. With PowerSync integration, themes automatically propagate between archives, ensuring consistency and enabling centralized theme management.

The system maintains backward compatibility with existing filesystem themes while providing new capabilities for dynamic theme management, asset optimization, and cross-archive synchronization. 