class JukeboxKey < ApplicationRecord
  validates :name, presence: true
  validates :key_hash, presence: true
  
  scope :active, -> { where(is_active: true) }
  
  # Store only the hash, never the original key
  def key_hash=(value)
    if value.length == 64  # Original key (hex string)
      super(BCrypt::Password.create(value))
    else  # Already hashed
      super(value)
    end
  end
  
  # Verify a key without storing original
  def verify_key(key)
    return false unless key.present?
    BCrypt::Password.new(key_hash) == key
  end
  
  # Generate new key and return original (display once)
  def self.generate_key(name, allowed_archives = [])
    original_key = SecureRandom.hex(32)
    
    jukebox_key = create!(
      name: name,
      allowed_archives: allowed_archives,
      key_hash: original_key  # Will be hashed by setter
    )
    
    # Return original key for one-time display
    original_key
  end
  
  # Regenerate key for existing jukebox
  def regenerate_key
    original_key = SecureRandom.hex(32)
    
    update!(
      key_hash: original_key,  # Will be hashed by setter
      last_used_at: nil  # Reset usage tracking
    )
    
    # Return original key for one-time display
    original_key
  end
  
  # Check if jukebox can access a specific archive
  def can_access_archive?(archive_node_id)
    allowed_archives.include?(archive_node_id)
  end
  
  # Add archive to allowed list
  def add_allowed_archive(archive_node_id)
    return if allowed_archives.include?(archive_node_id)
    
    self.allowed_archives ||= []
    self.allowed_archives << archive_node_id
    save!
  end
  
  # Remove archive from allowed list
  def remove_allowed_archive(archive_node_id)
    return unless allowed_archives.include?(archive_node_id)
    
    self.allowed_archives.delete(archive_node_id)
    save!
  end
  
  # Update last used timestamp
  def mark_used
    update!(last_used_at: Time.current)
  end
  
  # Deactivate key
  def deactivate
    update!(is_active: false)
  end
  
  # Reactivate key
  def reactivate
    update!(is_active: true)
  end
end 