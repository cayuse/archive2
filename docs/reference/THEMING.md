# Theming System Documentation

This application uses a flexible CSS-based theming system that allows for easy customization of colors, layouts, and component positioning without modifying HTML templates.

## Overview

The theming system is built on CSS custom properties (variables) and semantic CSS classes. This approach provides:

- **Separation of concerns**: Colors and styling are defined in CSS, not HTML
- **Easy theme switching**: Change themes by adding/removing CSS classes
- **Flexible layouts**: Components can be repositioned without HTML changes
- **Responsive design**: Themes adapt to different screen sizes
- **Accessibility**: Built-in support for high-contrast themes

## CSS Variables

The core of the theming system is CSS custom properties defined in `:root`:

```css
:root {
  --primary-bg: #0f0f23;
  --secondary-bg: #1a1a2e;
  --card-bg: #16213e;
  --accent-color: #4f46e5;
  --text-primary: #f8fafc;
  --text-secondary: #cbd5e1;
  --text-muted: #64748b;
  /* ... more variables */
}
```

## Semantic CSS Classes

Instead of hard-coding colors in HTML, use these semantic classes:

### Text Colors
- `.theme-text-primary` - Primary text color
- `.theme-text-secondary` - Secondary text color  
- `.theme-text-muted` - Muted text color
- `.theme-text-light` - Light text color

### Background Colors
- `.theme-bg-primary` - Primary background
- `.theme-bg-secondary` - Secondary background
- `.theme-bg-card` - Card background

### Component Classes
- `.theme-card-content` - Card content with proper text colors
- `.theme-form-label` - Form label styling
- `.theme-form-help` - Help text styling

## Available Themes

### Default Dark Theme
The default theme with dark colors and blue accents.

### Light Theme
```html
<body class="theme-light">
```
Clean, light interface with blue accents.

### High Contrast Theme
```html
<body class="theme-high-contrast">
```
High contrast theme for accessibility with bright colors on dark backgrounds.

### Sunset Theme
```html
<body class="theme-sunset">
```
Warm orange and brown color scheme.

### Ocean Theme
```html
<body class="theme-ocean">
```
Cool blue ocean-inspired colors.

## Layout Options

### Default Layout
Standard layout with top navigation.

### Sidebar Layout
```html
<body class="theme-layout-sidebar">
```
Navigation moves to a sidebar on the left.

### Center Layout
```html
<body class="theme-layout-center">
```
Content is centered with max-width.

### Full Width Layout
```html
<body class="theme-layout-fullwidth">
```
Content uses full viewport width.

## Combining Themes and Layouts

You can combine themes and layouts:

```html
<body class="theme-ocean theme-layout-sidebar">
```

## Usage in HTML

### Before (Hard-coded colors)
```html
<div class="card-body text-white">
  <dt class="text-white">Title:</dt>
  <dd class="text-white">Song Title</dd>
</div>
```

### After (Semantic classes)
```html
<div class="card-body theme-card-content">
  <dt class="theme-text-primary">Title:</dt>
  <dd class="theme-text-primary">Song Title</dd>
</div>
```

## Creating Custom Themes

To create a new theme:

1. Add a new CSS class in `app/assets/stylesheets/themes.css`:

```css
.theme-custom {
  --primary-bg: #your-color;
  --secondary-bg: #your-color;
  --card-bg: #your-color;
  --accent-color: #your-color;
  --text-primary: #your-color;
  --text-secondary: #your-color;
  --text-muted: #your-color;
  --border-color: #your-color;
  /* ... other variables */
}
```

2. Apply the theme:
```html
<body class="theme-custom">
```

## Theme Switcher Component

Include the theme switcher in your layout:

```erb
<%= render 'layouts/theme_switcher' %>
```

This provides a dropdown menu to switch between themes and layouts, with persistence using localStorage.

## Responsive Design

Themes automatically adapt to different screen sizes:

- **Mobile**: Sidebar layouts stack vertically
- **Tablet**: Adjusted spacing and sizing
- **Desktop**: Full layout options available

## Accessibility Features

- High contrast theme for visual impairments
- Semantic color classes for screen readers
- Flexible layouts for different viewing preferences
- Keyboard navigation support

## Best Practices

1. **Use semantic classes**: Always use `.theme-text-primary` instead of `text-white`
2. **Test with different themes**: Ensure your content works with all themes
3. **Consider accessibility**: Test with high contrast theme
4. **Keep layouts flexible**: Don't hard-code positioning
5. **Document custom themes**: Add comments explaining color choices

## File Structure

```
app/assets/stylesheets/
├── application.css          # Main styles with CSS variables
├── themes.css              # Theme definitions
└── app.css                 # Additional styles

app/views/layouts/
└── _theme_switcher.html.erb # Theme switcher component
```

## Migration Guide

To migrate existing hard-coded colors:

1. Replace `text-white` with `theme-text-primary`
2. Replace `text-light` with `theme-text-secondary`
3. Replace `text-muted` with `theme-text-muted`
4. Replace `card-body text-white` with `card-body theme-card-content`
5. Replace form labels with `theme-form-label`

## Examples

### Card with proper theming:
```html
<div class="card">
  <div class="card-header">
    <h5 class="mb-0">Song Information</h5>
  </div>
  <div class="card-body theme-card-content">
    <dl class="row">
      <dt class="col-sm-4 theme-text-primary">Title:</dt>
      <dd class="col-sm-8 theme-text-primary">Song Title</dd>
    </dl>
  </div>
</div>
```

### Form with proper theming:
```html
<div class="mb-3">
  <%= form.label :title, class: "form-label theme-form-label" %>
  <%= form.text_field :title, class: "form-control" %>
  <small class="theme-form-help">Help text here</small>
</div>
```

This theming system provides maximum flexibility while maintaining clean, semantic HTML that's easy to maintain and customize. 