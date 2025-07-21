class Theme < ApplicationRecord
  has_many :theme_assets, dependent: :destroy
  
  # Asset associations
  has_many :icons, -> { where(asset_type: 'icon') }, class_name: 'ThemeAsset'
  has_many :images, -> { where(asset_type: 'image') }, class_name: 'ThemeAsset'
  has_many :logos, -> { where(asset_type: 'logo') }, class_name: 'ThemeAsset'
  
  validates :name, presence: true, uniqueness: true, format: { with: /\A[a-z0-9_-]+\z/ }
  validates :display_name, presence: true
  
  # Color validations
  validates :primary_bg, :secondary_bg, :accent_color, :accent_hover, :accent_active,
            :text_primary, :text_secondary, :text_muted, :text_inverse,
            :border_color, :success_color, :warning_color, :danger_color,
            :button_bg, :button_hover, :button_active, :highlight_color,
            :link_color, :link_hover,
            presence: true, format: { with: /\A#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})\z/ }
  
  validates :shadow_color, :overlay_color,
            presence: true, format: { with: /\A(rgba?\([^)]+\)|#[A-Fa-f0-9]{6}|#[A-Fa-f0-9]{3})\z/ }
  
  scope :active, -> { where(is_active: true) }
  scope :default, -> { where(is_default: true) }
  
  # PowerSync integration (commented out for now)
  # include PowerSync::Model
  
  def self.current
    active.first || default.first || first
  end
  
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
      '--link-hover' => link_hover
    }
  end
  
  def generate_css
    ThemeCssGenerator.generate_for_theme(self)
  end
  
  def asset_by_type_and_filename(asset_type, filename)
    theme_assets.find_by(asset_type: asset_type, filename: filename)
  end
  
  def duplicate!
    new_theme = dup
    new_theme.name = "#{name}_copy_#{Time.current.to_i}"
    new_theme.display_name = "#{display_name} (Copy)"
    new_theme.is_default = false
    new_theme.is_active = false
    
    if new_theme.save
      # Duplicate assets
      theme_assets.each do |asset|
        new_asset = asset.dup
        new_asset.theme = new_theme
        new_asset.save!
      end
      new_theme
    else
      false
    end
  end
end
