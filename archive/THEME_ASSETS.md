# Theme Assets System

## Overview

The theme system supports organized asset management with separate folders for different types of assets.

## Directory Structure

```
app/assets/images/themes/{theme_name}/
├── logo.svg                    # Theme logo
├── icons/                      # Theme-specific icons
│   ├── music-note.svg
│   ├── play.svg
│   ├── pause.svg
│   └── volume.svg
└── images/                     # Theme-specific images
    ├── background-pattern.svg
    └── other-images.png
```

## Helper Methods

### Icon Helpers
```erb
<!-- Display an icon -->
<%= theme_icon_tag('play.svg') %>

<!-- With custom options -->
<%= theme_icon_tag('play.svg', width: 32, height: 32, class: 'custom-class') %>

<!-- Get icon path -->
<%= theme_icon_path('play.svg') %>
```

### Image Helpers
```erb
<!-- Display an image -->
<%= theme_image_tag('background-pattern.svg') %>

<!-- With custom options -->
<%= theme_image_tag('background.svg', class: 'img-fluid', style: 'max-width: 200px;') %>

<!-- Get image path -->
<%= theme_image_path('background.svg') %>
```

### Logo Helper
```erb
<!-- Display theme logo -->
<img src="<%= theme_logo_path %>" alt="Logo">

<!-- Get logo path -->
<%= theme_logo_path %>
```

### General Asset Helper
```erb
<!-- For any theme asset -->
<%= theme_asset_path('custom-asset.svg') %>
```

## Adding Assets to a Theme

### 1. Create Theme Directory
```bash
mkdir -p app/assets/images/themes/new-theme/icons
mkdir -p app/assets/images/themes/new-theme/images
```

### 2. Add Assets
```bash
# Add icons
cp my-icon.svg app/assets/images/themes/new-theme/icons/

# Add images
cp my-image.png app/assets/images/themes/new-theme/images/

# Add logo
cp my-logo.svg app/assets/images/themes/new-theme/logo.svg
```

### 3. Compile Assets
```bash
bin/rails assets:precompile
```

## Asset Types

### Icons
- **Location**: `icons/` folder
- **Format**: SVG recommended for scalability
- **Usage**: UI elements, buttons, navigation
- **Helper**: `theme_icon_tag()` and `theme_icon_path()`

### Images
- **Location**: `images/` folder
- **Format**: SVG, PNG, JPG supported
- **Usage**: Backgrounds, decorative elements
- **Helper**: `theme_image_tag()` and `theme_image_path()`

### Logo
- **Location**: Root theme folder
- **Format**: SVG recommended
- **Usage**: Brand identity, navigation
- **Helper**: `theme_logo_path()`

## Best Practices

### 1. File Naming
- Use kebab-case: `music-note.svg`
- Be descriptive: `play-button.svg` not `btn.svg`
- Include format: `background-pattern.svg`

### 2. SVG Optimization
- Use vector graphics when possible
- Optimize SVG files for web
- Include proper viewBox attributes

### 3. Asset Organization
- Group related icons together
- Use consistent naming conventions
- Document custom assets

### 4. Performance
- Use SVG for icons (scalable, small file size)
- Optimize images for web
- Consider lazy loading for large images

## Example Theme Structure

```
app/assets/images/themes/default/
├── logo.svg
├── icons/
│   ├── music-note.svg
│   ├── play.svg
│   ├── pause.svg
│   ├── volume.svg
│   ├── settings.svg
│   └── user.svg
└── images/
    ├── background-pattern.svg
    ├── hero-image.svg
    └── decorative-element.svg
```

## CSS Integration

Theme assets can be referenced in CSS using the asset pipeline:

```css
.theme-background {
  background-image: url(asset-path("themes/default/images/background-pattern.svg"));
}

.theme-icon {
  background-image: url(asset-path("themes/default/icons/music-note.svg"));
}
```

## Auto-Discovery

The system automatically discovers new themes and their assets:
1. Scans `app/assets/stylesheets/themes/` for theme CSS files
2. Scans `app/assets/images/themes/` for theme assets
3. Updates available themes in settings
4. Makes new assets immediately available

## Testing Assets

Visit the theme settings page to see a demo of all available theme assets for the current theme. 