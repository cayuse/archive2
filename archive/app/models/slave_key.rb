class SlaveKey < ApplicationRecord
  validates :name, presence: true
  validates :node_id, presence: true, uniqueness: true
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
  def self.generate_key(name, node_id)
    original_key = SecureRandom.hex(32)
    
    slave_key = create!(
      name: name,
      node_id: node_id,
      key_hash: original_key  # Will be hashed by setter
    )
    
    # Return original key for one-time display
    original_key
  end
  
  # Regenerate key for existing slave
  def regenerate_key
    original_key = SecureRandom.hex(32)
    
    update!(
      key_hash: original_key,  # Will be hashed by setter
      last_used_at: nil  # Reset usage tracking
    )
    
    # Return original key for one-time display
    original_key
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