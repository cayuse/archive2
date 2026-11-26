# 🎨 Theming System Guide

## Overview

The music archive uses a **hierarchical theming system** that allows for both **broad** and **granular** theme customization. This system provides maximum flexibility while maintaining consistency.

## 🏗️ Hierarchical Structure

### **Master Systems** (Broad Theming)
All components inherit from master systems. Change these to affect the entire application:

```css
/* Master Card System */
[data-theme="your-theme"] .card { /* All cards */ }
[data-theme="your-theme"] .card-header { /* All card headers */ }
[data-theme="your-theme"] .card-body { /* All card bodies */ }

/* Master Button System */
[data-theme="your-theme"] .btn { /* All buttons */ }
[data-theme="your-theme"] .btn-primary { /* All primary buttons */ }

/* Master Form System */
[data-theme="your-theme"] .form-control { /* All form inputs */ }
[data-theme="your-theme"] .form-select { /* All select dropdowns */ }

/* Master Table System */
[data-theme="your-theme"] .table { /* All tables */ }
[data-theme="your-theme"] .table th { /* All table headers */ }
[data-theme="your-theme"] .table td { /* All table cells */ }
```

### **Granular Systems** (Specific Views)
Override master systems for specific views using semantic class names:

```css
/* Song View Cards */
[data-theme="your-theme"] .card.song-view-song-information { /* Song detail cards */ }
[data-theme="your-theme"] .card.song-list-song-item { /* Song list cards */ }

/* Artist View Cards */
[data-theme="your-theme"] .card.artist-view-artist-profile { /* Artist profile cards */ }

/* Album View Cards */
[data-theme="your-theme"] .card.album-view-album-details { /* Album detail cards */ }

/* Genre View Cards */
[data-theme="your-theme"] .card.genre-view-genre-info { /* Genre info cards */ }

/* Settings Cards */
[data-theme="your-theme"] .card.settings-view-settings-panel { /* Settings cards */ }

/* Upload Cards */
[data-theme="your-theme"] .card.upload-view-upload-form { /* Upload form cards */ }

/* Maintenance Cards */
[data-theme="your-theme"] .card.maintenance-view-song-item { /* Maintenance cards */ }

/* Stats Cards */
[data-theme="your-theme"] .card.stats-view-stats-card { /* Statistics cards */ }
```

## 🎯 Usage Examples

### **Option 1: Broad Theming (Quick & Easy)**
Only modify master systems for a complete theme change:

```css
[data-theme="my-theme"] {
  /* Change all colors */
  --primary-bg: #1a1a1a;
  --card-bg: #2d2d2d;
  --accent-color: #ff6b6b;
}

/* All cards will automatically use the new colors */
```

### **Option 2: Granular Theming (Precise Control)**
Customize specific views while keeping master styles:

```css
/* Keep master card styles, but customize song cards */
[data-theme="my-theme"] .card.song-view-song-information {
  border-left: 4px solid #ff6b6b;
  background: linear-gradient(135deg, var(--card-bg) 0%, rgba(255, 107, 107, 0.1) 100%);
}

[data-theme="my-theme"] .card.song-view-song-information .card-header {
  background: linear-gradient(135deg, #ff6b6b 0%, #ff8e8e 100%);
  color: white;
}
```

### **Option 3: Mixed Approach (Recommended)**
Use master systems for consistency, granular systems for emphasis:

```css
/* Master system for consistency */
[data-theme="my-theme"] .card {
  background: var(--card-bg);
  border-radius: 12px;
  box-shadow: var(--shadow-md);
}

/* Granular system for specific emphasis */
[data-theme="my-theme"] .card.stats-view-stats-card {
  background: var(--gradient-primary);
  color: white;
  border: none;
}
```

## 📋 Class Naming Convention

### **View-Based Classes**
Use the pattern: `[view-type]-view-[component-name]`

- `song-view-song-information` - Song detail pages
- `artist-view-artist-profile` - Artist profile pages
- `album-view-album-details` - Album detail pages
- `genre-view-genre-info` - Genre information pages
- `settings-view-settings-panel` - Settings pages
- `upload-view-upload-form` - Upload forms
- `maintenance-view-song-item` - Maintenance pages
- `stats-view-stats-card` - Statistics cards

### **List-Based Classes**
Use the pattern: `[item-type]-list-[item-name]`

- `song-list-song-item` - Song list items
- `artist-list-artist-item` - Artist list items
- `album-list-album-item` - Album list items

## 🎨 Theme Development Workflow

### **Step 1: Create Theme Directory**
```bash
mkdir app/assets/stylesheets/themes/your-theme
```

### **Step 2: Copy Default Theme**
```bash
cp app/assets/stylesheets/themes/default/theme.css app/assets/stylesheets/themes/your-theme/theme.css
```

### **Step 3: Update Theme Selector**
Change `[data-theme="default"]` to `[data-theme="your-theme"]`

### **Step 4: Customize Colors**
```css
[data-theme="your-theme"] {
  --primary-bg: #your-color;
  --secondary-bg: #your-color;
  --card-bg: #your-color;
  --accent-color: #your-color;
  /* ... other variables */
}
```

### **Step 5: Add Granular Customizations**
```css
/* Customize specific views */
[data-theme="your-theme"] .card.song-view-song-information {
  /* Your custom styles */
}
```

## 🔧 Implementation in Views

### **Adding Semantic Classes to Cards**

```erb
<!-- Song detail page -->
<div class="card song-view-song-information">
  <div class="card-header">Song Information</div>
  <div class="card-body">
    <!-- Content -->
  </div>
</div>

<!-- Artist profile page -->
<div class="card artist-view-artist-profile">
  <div class="card-header">Artist Profile</div>
  <div class="card-body">
    <!-- Content -->
  </div>
</div>

<!-- Settings page -->
<div class="card settings-view-settings-panel">
  <div class="card-header">Theme Settings</div>
  <div class="card-body">
    <!-- Content -->
  </div>
</div>
```

## 🎯 Benefits

### **For Theme Developers:**
- **Flexibility**: Choose broad or granular theming
- **Consistency**: Master systems ensure uniformity
- **Maintainability**: Clear structure and organization
- **Scalability**: Easy to add new themes

### **For Users:**
- **Impactful Changes**: Themes can completely transform the look
- **Consistent Experience**: All cards follow the same base design
- **Visual Hierarchy**: Different views have distinct styling
- **Accessibility**: Proper contrast and focus states

## 🚀 Quick Start

1. **Copy the default theme** as your starting point
2. **Change CSS variables** for broad theming
3. **Add granular classes** to views for specific styling
4. **Test both approaches** to find the right balance

## 📝 Best Practices

1. **Start with master systems** for consistency
2. **Use granular systems** for emphasis and variety
3. **Maintain accessibility** with proper contrast ratios
4. **Test on different screen sizes** for responsiveness
5. **Document your theme** for future maintenance

## 🎨 Example Themes

### **Minimal Theme**
```css
[data-theme="minimal"] {
  --primary-bg: #ffffff;
  --card-bg: #f8f9fa;
  --accent-color: #6c757d;
  /* Simple, clean design */
}
```

### **High Contrast Theme**
```css
[data-theme="high-contrast"] {
  --primary-bg: #000000;
  --card-bg: #ffffff;
  --accent-color: #ffff00;
  /* Maximum contrast for accessibility */
}
```

### **Colorful Theme**
```css
[data-theme="colorful"] {
  --accent-color: #ff6b6b;
  /* Add granular customizations for each view */
}
[data-theme="colorful"] .card.song-view-song-information {
  border-left: 4px solid #ff6b6b;
}
```

This hierarchical system gives you the power to create both subtle and dramatic theme changes while maintaining a consistent, professional appearance across your music archive application. 