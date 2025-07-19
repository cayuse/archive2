class SyncChange < ApplicationRecord
  validates :table_name, presence: true
  validates :record_id, presence: true
  validates :change_type, presence: true, inclusion: { in: %w[create update delete] }
  
  scope :unapplied, -> { where(applied_at: nil) }
  scope :since, ->(timestamp) { where('created_at > ?', timestamp) }
  scope :for_table, ->(table) { where(table_name: table) }
  
  # Track which slaves have applied this change
  def mark_applied_by_slave(slave_node_id)
    self.applied_to_slaves ||= []
    self.applied_to_slaves << slave_node_id unless self.applied_to_slaves.include?(slave_node_id)
    self.applied_at = Time.current if self.applied_at.nil?
    save!
  end
  
  # Check if change has been applied by a specific slave
  def applied_by_slave?(slave_node_id)
    applied_to_slaves&.include?(slave_node_id) || false
  end
  
  # Get the model class for this change
  def model_class
    table_name.classify.constantize
  rescue NameError
    nil
  end
  
  # Get the actual record (if it still exists)
  def record
    return nil unless model_class
    
    case change_type
    when 'delete'
      nil # Record was deleted
    else
      model_class.find_by(id: record_id)
    end
  end
  
  # Apply this change to the local database
  def apply_locally
    return false unless model_class
    
    case change_type
    when 'create'
      if change_data.present?
        model_class.create!(change_data.except('id', 'created_at', 'updated_at'))
      end
    when 'update'
      record = model_class.find_by(id: record_id)
      if record && change_data.present?
        record.update!(change_data.except('id', 'created_at', 'updated_at'))
      end
    when 'delete'
      record = model_class.find_by(id: record_id)
      record&.destroy
    end
    
    true
  rescue => e
    Rails.logger.error "Failed to apply sync change #{id}: #{e.message}"
    false
  end
end 