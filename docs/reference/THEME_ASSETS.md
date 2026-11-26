# Theme assets

Images that belong to a theme: logos, icons and other images. They are stored in the
database, not in `app/assets`. For colours and theme management see `THEMING.md`.

## Storage

Table `theme_assets`, model `ThemeAsset`, `belongs_to :theme`:

| Column | |
|---|---|
| `asset_type` | `logo`, `icon` or `image` |
| `filename` | unique per theme and asset type |
| `display_name`, `description` | |
| `file_data` | the file itself (`bytea`) |
| `content_type`, `file_size` | |
| `checksum` | SHA-256 of `file_data` (`ThemeAsset#validate_checksum!` checks it) |

`Theme` has `theme_assets` plus `logos`, `icons` and `images` scoped by type. Deleting a
theme deletes its assets; duplicating a theme copies them.

## Serving

`GET /themes/:theme/assets/:asset_type/:filename` (`ThemesController#asset`, no login)
sends the file inline with its stored content type, or 404. `:theme` is the theme's `name`,
`:asset_type` is singular (`logo`, `icon`, `image`).

## Helpers

In `ApplicationHelper`, all relative to the current theme:

| Helper | Returns |
|---|---|
| `theme_asset_path(asset_type, filename)` | `/themes/<current>/assets/<asset_type>/<filename>` |
| `theme_logo_path` | the path of the theme's first logo, or `/icon.svg` if it has none |
| `theme_icon_path(filename)` | the icon's path if the theme has it, else `/icon.svg` |
| `theme_image_path(filename)` | the image's path if the theme has it, else `/icon.svg` |
| `current_theme`, `theme_css_path` | the theme's name; its stylesheet URL |

The navigation bar's logo is `theme_logo_path`. There are no `theme_icon_tag` /
`theme_image_tag` helpers; use `image_tag theme_icon_path("play.svg")`.

## Adding an asset

There is no upload form. The theme's page (`/themes/:id`) lists its icons, images and
logos but cannot add or remove them. Add one from the Rails console:

```ruby
theme = Theme.find_by!(name: "default")
File.open("logo.svg", "rb") do |f|
  data = f.read
  theme.theme_assets.create!(
    asset_type: "logo", filename: "logo.svg", display_name: "Logo",
    file_data: data, content_type: "image/svg+xml",
    checksum: Digest::SHA256.hexdigest(data), file_size: data.bytesize
  )
end
```

(`ThemeAsset.create_from_upload(theme, asset_type, uploaded_file, display_name)` does the
same for an `ActionDispatch::Http::UploadedFile`; no controller calls it.)

`ThemeAsset::STANDARD_ICONS` and `STANDARD_IMAGES` list conventional file names
(`songs.png`, `background.jpg`, …); nothing requires or uses them.

## Not used

`app/views/settings/_theme_demo.html.erb` is left over from the old file-based assets. It is
not rendered anywhere and calls helpers that no longer exist.
