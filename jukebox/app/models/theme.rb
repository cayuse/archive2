class Theme < ApplicationRecord
  has_many :theme_assets, dependent: :destroy

  # Asset associations
  has_many :icons, -> { where(asset_type: 'icon') }, class_name: 'ThemeAsset'
  has_many :images, -> { where(asset_type: 'image') }, class_name: 'ThemeAsset'
  has_many :logos, -> { where(asset_type: 'logo') }, class_name: 'ThemeAsset'

  # Validations
  validates :name, presence: true, uniqueness: true, length: { maximum: 100 }
  validates :display_name, presence: true, length: { maximum: 200 }
  validates :description, length: { maximum: 500 }

  # Scopes
  scope :active, -> { where(is_active: true) }
  scope :default, -> { where(is_default: true) }
  scope :by_name, -> { order(:name) }
  scope :by_display_name, -> { order(:display_name) }

  # Class methods
  def self.current
    active.first || default.first || first
  end

  # CSS variables hash for the theme
  def css_variables
    {
      '--primary-color' => primary_color,
      '--secondary-color' => secondary_color,
      '--accent-color' => accent_color,
      '--background-color' => background_color,
      '--surface-color' => surface_color,
      '--text-color' => text_color,
      '--text-muted-color' => text_muted_color,
      '--border-color' => border_color,
      '--success-color' => success_color,
      '--warning-color' => warning_color,
      '--error-color' => error_color,
      '--info-color' => info_color,
      '--link-color' => link_color,
      '--link-hover-color' => link_hover_color,
      '--button-primary-bg' => button_primary_bg,
      '--button-primary-text' => button_primary_text,
      '--button-secondary-bg' => button_secondary_bg,
      '--button-secondary-text' => button_secondary_text,
      '--card-bg' => card_bg,
      '--card-border' => card_border,
      '--navbar-bg' => navbar_bg
    }
  end

  # Generate CSS for this theme
  def generate_css
    ThemeCssGenerator.generate_for_theme(self)
  end

  # Get asset by type and filename
  def get_asset(asset_type, filename)
    theme_assets.find_by(asset_type: asset_type, filename: filename)
  end

  # Duplicate theme
  def duplicate
    new_theme = dup
    new_theme.name = "#{name}_copy_#{Time.current.to_i}"
    new_theme.display_name = "#{display_name} (Copy)"
    new_theme.is_default = false
    new_theme.is_active = false
    
    if new_theme.save
      # Copy theme assets
      theme_assets.each do |asset|
        new_asset = asset.dup
        new_asset.theme = new_theme
        new_asset.save!
      end
    end
    
    new_theme
  end
end 