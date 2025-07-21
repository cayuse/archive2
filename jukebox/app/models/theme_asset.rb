class ThemeAsset < ApplicationRecord
  belongs_to :theme

  # Active Storage for file uploads
  has_one_attached :file

  # Validations
  validates :asset_type, presence: true, inclusion: { in: %w[icon image logo] }
  validates :filename, presence: true, length: { maximum: 255 }
  validates :display_name, presence: true, length: { maximum: 200 }
  validates :filename, uniqueness: { scope: [:theme_id, :asset_type] }

  # Scopes
  scope :icons, -> { where(asset_type: 'icon') }
  scope :images, -> { where(asset_type: 'image') }
  scope :logos, -> { where(asset_type: 'logo') }
  scope :by_filename, -> { order(:filename) }

  # Instance methods
  def file_url
    if file.attached?
      file
    else
      # Fallback to stored URL if file not attached
      url.presence
    end
  end

  def file_size
    if file.attached?
      file.byte_size
    else
      size || 0
    end
  end

  def content_type
    if file.attached?
      file.content_type
    else
      mime_type.presence || 'application/octet-stream'
    end
  end

  def extension
    File.extname(filename).downcase if filename.present?
  end

  def is_image?
    content_type.start_with?('image/')
  end

  def is_svg?
    content_type == 'image/svg+xml' || extension == '.svg'
  end

  def thumbnail_url
    if is_image? && !is_svg? && file.attached?
      file.representation(resize_to_limit: [100, 100])
    else
      file_url
    end
  end

  # Class methods
  def self.create_from_upload(theme, asset_type, file, display_name, description = nil)
    filename = file.original_filename
    
    theme_asset = new(
      theme: theme,
      asset_type: asset_type,
      filename: filename,
      display_name: display_name,
      description: description,
      size: file.size,
      mime_type: file.content_type
    )
    
    theme_asset.file.attach(file)
    theme_asset.save!
    theme_asset
  end
end 