class Theme < ApplicationRecord
  has_many :theme_assets, dependent: :destroy

  # Asset associations (shared DB with Archive)
  has_many :icons, -> { where(asset_type: 'icon') }, class_name: 'ThemeAsset'
  has_many :images, -> { where(asset_type: 'image') }, class_name: 'ThemeAsset'
  has_many :logos,  -> { where(asset_type: 'logo')  }, class_name: 'ThemeAsset'

  # Match Archive validations
  validates :name, presence: true, uniqueness: true, format: { with: /\A[a-z0-9_-]+\z/ }
  validates :display_name, presence: true

  validates :primary_bg, :secondary_bg, :accent_color, :accent_hover, :accent_active,
            :text_primary, :text_secondary, :text_muted, :text_inverse,
            :border_color, :success_color, :warning_color, :danger_color,
            :button_bg, :button_hover, :button_active, :highlight_color,
            :link_color, :link_hover,
            presence: true, format: { with: /\A#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})\z/ }

  validates :shadow_color, :overlay_color,
            presence: true, format: { with: /\A(rgba?\([^)]+\)|#[A-Fa-f0-9]{6}|#[A-Fa-f0-9]{3})\z/ }

  scope :default, -> { where(is_default: true) }
  scope :by_name, -> { order(:name) }
  scope :by_display_name, -> { order(:display_name) }

  def self.current
    name = SystemSetting.current_theme
    Theme.find_by(name: name) || default.first || first
  end

  # Align CSS variables to Archive naming
  def css_variables
    {
      '--primary-bg' => primary_bg,
      '--secondary-bg' => secondary_bg,
      '--accent-color' => accent_color,
      '--accent-hover' => accent_hover,
      '--accent-active' => accent_active,
      '--text-primary' => text_primary,
      '--text-secondary' => text_secondary,
      '--text-muted' => text_muted,
      '--text-inverse' => text_inverse,
      '--border-color' => border_color,
      '--shadow-color' => shadow_color,
      '--overlay-color' => overlay_color,
      '--success-color' => success_color,
      '--warning-color' => warning_color,
      '--danger-color' => danger_color,
      '--button-bg' => button_bg,
      '--button-hover' => button_hover,
      '--button-active' => button_active,
      '--highlight-color' => highlight_color,
      '--link-color' => link_color,
      '--link-hover' => link_hover,
      '--heading-color' => (respond_to?(:heading_color) ? (heading_color.presence || text_primary) : text_primary),
      '--card-header-text' => (respond_to?(:card_header_text) ? (card_header_text.presence || text_primary) : text_primary)
    }
  end

  def generate_css
    ThemeCssGenerator.generate_for_theme(self)
  end

  def get_asset(asset_type, filename)
    theme_assets.find_by(asset_type: asset_type, filename: filename)
  end
end