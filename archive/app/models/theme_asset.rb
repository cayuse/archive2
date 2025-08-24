class ThemeAsset < ApplicationRecord
  belongs_to :theme
  
  validates :asset_type, presence: true, inclusion: { in: %w[icon image logo] }
  validates :filename, presence: true
  validates :display_name, presence: true
  validates :file_data, presence: true
  validates :content_type, presence: true
  validates :checksum, presence: true
  validates :file_size, presence: true, numericality: { greater_than: 0 }
  
  validates :filename, uniqueness: { scope: [:theme_id, :asset_type] }
  

  
  # Asset type scopes
  scope :icons, -> { where(asset_type: 'icon') }
  scope :images, -> { where(asset_type: 'image') }
  scope :logos, -> { where(asset_type: 'logo') }
  
  # Standard asset filenames
  STANDARD_ICONS = %w[
    songs.png genres.png artists.png albums.png playlists.png
    settings.png upload.png search.png user.png home.png
  ].freeze
  
  STANDARD_IMAGES = %w[
    background.jpg logo.png favicon.ico
  ].freeze
  
  def self.standard_assets
    {
      icons: STANDARD_ICONS,
      images: STANDARD_IMAGES
    }
  end
  
  def file_extension
    File.extname(filename).downcase
  end
  
  def image?
    content_type.start_with?('image/')
  end
  
  def svg?
    content_type == 'image/svg+xml'
  end
  
  def png?
    content_type == 'image/png'
  end
  
  def jpg?
    content_type == 'image/jpeg'
  end
  
  def ico?
    content_type == 'image/x-icon'
  end
  
  def generate_checksum
    Digest::SHA256.hexdigest(file_data)
  end
  
  def validate_checksum!
    actual_checksum = generate_checksum
    if actual_checksum != checksum
      raise "Checksum mismatch for #{filename}"
    end
  end
  
  def self.create_from_upload(theme, asset_type, file, display_name, description = nil)
    content = file.read
    checksum = Digest::SHA256.hexdigest(content)
    
    create!(
      theme: theme,
      asset_type: asset_type,
      filename: file.original_filename,
      display_name: display_name,
      description: description,
      file_data: content,
      content_type: file.content_type,
      checksum: checksum,
      file_size: file.size
    )
  end
end 