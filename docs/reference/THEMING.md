# Theming

A theme in The Archive is a row in the database holding a set of colours. The app turns the
active theme into CSS custom properties, and the stylesheets are written in terms of those
properties. One theme is active for the whole site; there is no per-user theme.

Theme images (logo, icons) are covered in `THEME_ASSETS.md`.

## How it fits together

1. `Theme` (table `themes`) stores the colours. `SystemSetting` key `current_theme` holds
   the name of the active one. `Theme.current` returns it, falling back to the theme marked
   `is_default`, then to the first theme.
2. The layout (`app/views/layouts/application.html.erb`) puts `data-theme="<name>"` on
   `<html>` and `<body>` and loads, in order: Bootstrap, the app's own stylesheet
   (`application.css`, which pulls in `app.css` and `theme.css`), and the generated theme
   stylesheet `/themes/<name>.css?v=<theme updated_at>`.
3. `GET /themes/:theme.css` (`ThemesController#css`, no login, cached for an hour) returns
   CSS built by `ThemeCssGenerator`: the theme's variables under `[data-theme="<name>"]` and
   again under `:root`, the spacing / radius / shadow variables, and a handful of base rules
   (body, headings, `.card`, `.btn-primary`).
4. `app/assets/stylesheets/theme.css` holds the real styling. It defines the same variables
   with the default theme's values (so pages look right before the generated sheet loads)
   and styles components with `var(--…)`.

Changing a theme's colours therefore needs no deploy: save the theme and reload.

## Variables

Each is a column on `themes` (underscores instead of dashes, no leading `--`).

| Variable | Default | |
|---|---|---|
| `--primary-bg` | `#0f0f23` | page background |
| `--secondary-bg` | `#1a1a2e` | cards, panels |
| `--accent-color`, `--accent-hover`, `--accent-active` | `#4f46e5`, `#6366f1`, `#3730a3` | primary buttons, accents |
| `--text-primary`, `--text-secondary`, `--text-muted`, `--text-inverse` | `#f8fafc`, `#cbd5e1`, `#64748b`, `#ffffff` | text |
| `--border-color` | `#334155` | |
| `--shadow-color`, `--overlay-color` | `rgba(0, 0, 0, 0.1)`, `rgba(0, 0, 0, 0.5)` | |
| `--success-color`, `--warning-color`, `--danger-color` | `#10b981`, `#f59e0b`, `#ef4444` | |
| `--button-bg`, `--button-hover`, `--button-active` | `#374151`, `#4b5563`, `#1f2937` | secondary buttons |
| `--highlight-color` | `#3b82f6` | |
| `--link-color`, `--link-hover` | `#60a5fa`, `#93c5fd` | |
| `--heading-color`, `--card-header-text` | (blank) | optional; fall back to `--text-primary` |

Colours must be hex (`#rgb` or `#rrggbb`). `shadow_color` and `overlay_color` may also be
`rgb()` / `rgba()`. There is no `--card-bg`; cards use `--secondary-bg`.

Not theme-specific, but available everywhere: `--spacing-xs` … `--spacing-xl`,
`--radius-sm` … `--radius-xl`, `--shadow-sm` / `-md` / `-lg`.

The `themes` table also has `css_variables` (jsonb) and `custom_css` (text). They are stored
but nothing reads them: a theme cannot currently add its own CSS rules, only change colours.

## Managing themes

Admins only: **System Settings → Theme** (`/themes`, handled by `SettingsController`).

| Action | Route |
|---|---|
| List | `GET /themes` |
| New / create | `GET /themes/new`, `POST /themes` |
| Show (colours and assets) | `GET /themes/:id` |
| Edit / update | `GET /themes/:id/edit`, `PATCH /themes/:id` |
| Delete (not the default theme) | `DELETE /themes/:id` |
| Duplicate (copies colours and assets; named `<name>_copy_<timestamp>`) | `POST /themes/:id/duplicate` |
| Make active | `POST /themes/:id/switch` |
| Export | `GET /themes/:id/export` |

A theme's `name` is its identifier in URLs and in `data-theme`: lower-case letters, digits,
`-` and `_` only. `display_name` is what people see.

Export writes the generated CSS and the theme's assets to
`app/assets/stylesheets/themes/<name>/` on the server's filesystem; it does not download
anything. In the production container that directory is lost on the next deploy.

`GET /themes/:id/preview` is routed but has no template.

`bin/rails db:seed` creates the `default` theme and sets it as current.

## Writing views and CSS

Use the variables, or the helper classes from `theme.css`, instead of fixed colours or
Bootstrap's `text-white` / `text-light`:

| Class | |
|---|---|
| `.theme-text-primary`, `.theme-text-secondary`, `.theme-text-muted`, `.theme-text-inverse` | text colour |
| `.theme-bg-primary`, `.theme-bg-secondary` | background |
| `.theme-border` | border colour |
| `.theme-shadow-sm`, `.theme-shadow-md`, `.theme-shadow-lg` | box shadow |
| `.theme-card-content` | a card body with themed text |
| `.theme-form-label`, `.theme-form-help` | form label and help text |

```erb
<div class="card">
  <div class="card-header"><h5 class="mb-0">Song Information</h5></div>
  <div class="card-body theme-card-content">
    <dl class="row">
      <dt class="col-sm-4 theme-text-primary">Title:</dt>
      <dd class="col-sm-8 theme-text-primary"><%= @song.title %></dd>
    </dl>
  </div>
</div>

<div class="mb-3">
  <%= form.label :title, class: "form-label theme-form-label" %>
  <%= form.text_field :title, class: "form-control" %>
  <small class="theme-form-help">Help text here</small>
</div>
```

```css
.my-widget {
  background: var(--secondary-bg);
  color: var(--text-primary);
  border: 1px solid var(--border-color);
  border-radius: var(--radius-md);
}
```

Rules that should apply to one theme only can be scoped with `[data-theme="<name>"]` in
`theme.css`, but that is a code change, not something a theme record can carry.

## Leftovers from the old file-based system

Themes used to be directories of CSS and images under `app/assets`. Those directories are
gone, but some code that assumed them remains and is not used:

- `app/views/layouts/_theme_switcher.html.erb` (a browser-side switcher for `theme-light`,
  `theme-ocean` and similar body classes that no longer exist) and
  `app/views/settings/themes/_switcher.html.erb` — neither is rendered anywhere;
- `SystemSetting.available_themes` and the `tab=theme` branch of `SettingsController#update`,
  which look for themes on disk;
- `ThemeMigrationService`, which imported file-based themes into the database.

The per-view card classes (`song-view-song-information`, `settings-view-settings-panel`, …)
and the body layout classes (`theme-layout-sidebar`, …) described in earlier versions of
this document do not exist.
