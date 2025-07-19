class ConflictResolutionService
  include Singleton

  # Resolve conflicts between master and slave changes
  def resolve_conflicts(master_changes, slave_changes)
    conflicts = detect_conflicts(master_changes, slave_changes)
    
    resolved_changes = []
    conflicts.each do |conflict|
      resolution = resolve_conflict(conflict[:master_change], conflict[:slave_change])
      resolved_changes << resolution if resolution
    end
    
    resolved_changes
  end

  # Detect conflicts between master and slave changes
  def detect_conflicts(master_changes, slave_changes)
    conflicts = []
    
    master_changes.each do |master_change|
      slave_changes.each do |slave_change|
        if same_record?(master_change, slave_change)
          conflict_type = determine_conflict_type(master_change, slave_change)
          if conflict_type != :no_conflict
            conflicts << {
              type: conflict_type,
              master_change: master_change,
              slave_change: slave_change
            }
          end
        end
      end
    end
    
    conflicts
  end

  # Resolve a single conflict
  def resolve_conflict(master_change, slave_change)
    conflict_type = determine_conflict_type(master_change, slave_change)
    
    case conflict_type
    when :simultaneous_update
      resolve_simultaneous_update(master_change, slave_change)
    when :deletion_vs_update
      resolve_deletion_vs_update(master_change, slave_change)
    when :simultaneous_deletion
      resolve_simultaneous_deletion(master_change, slave_change)
    when :creation_vs_update
      resolve_creation_vs_update(master_change, slave_change)
    else
      nil # No conflict to resolve
    end
  end

  private

  def same_record?(change1, change2)
    change1['table'] == change2['table'] && 
    change1['record_id'] == change2['record_id']
  end

  def determine_conflict_type(master_change, slave_change)
    master_type = master_change['type']
    slave_type = slave_change['type']
    
    case [master_type, slave_type]
    when ['update', 'update']
      :simultaneous_update
    when ['delete', 'update'], ['update', 'delete']
      :deletion_vs_update
    when ['delete', 'delete']
      :simultaneous_deletion
    when ['create', 'update'], ['update', 'create']
      :creation_vs_update
    else
      :no_conflict
    end
  end

  def resolve_simultaneous_update(master_change, slave_change)
    # Simple timestamp-based resolution
    master_time = Time.parse(master_change['timestamp'])
    slave_time = Time.parse(slave_change['timestamp'])
    
    if master_time > slave_time
      {
        action: :apply_master,
        change: master_change,
        reason: "Master change is more recent (#{master_time} vs #{slave_time})"
      }
    else
      {
        action: :apply_slave,
        change: slave_change,
        reason: "Slave change is more recent (#{slave_time} vs #{master_time})"
      }
    end
  end

  def resolve_deletion_vs_update(master_change, slave_change)
    # Deletion always takes precedence over update
    if master_change['type'] == 'delete'
      {
        action: :apply_master,
        change: master_change,
        reason: "Master deletion takes precedence over slave update"
      }
    else
      {
        action: :apply_slave,
        change: slave_change,
        reason: "Slave deletion takes precedence over master update"
      }
    end
  end

  def resolve_simultaneous_deletion(master_change, slave_change)
    # Both deleted - no conflict, either deletion is fine
    {
      action: :apply_master,
      change: master_change,
      reason: "Both archives deleted the same record - using master deletion"
    }
  end

  def resolve_creation_vs_update(master_change, slave_change)
    # Creation vs update - this shouldn't happen with proper initial sync
    # But if it does, creation takes precedence
    if master_change['type'] == 'create'
      {
        action: :apply_master,
        change: master_change,
        reason: "Master creation takes precedence over slave update"
      }
    else
      {
        action: :apply_slave,
        change: slave_change,
        reason: "Slave creation takes precedence over master update"
      }
    end
  end

  # Log conflict resolution for audit trail
  def log_conflict_resolution(conflict, resolution)
    Rails.logger.info "Conflict resolved: #{conflict[:type]} - #{resolution[:reason]}"
    
    # Store in database for audit trail if needed
    ConflictLog.create!(
      conflict_type: conflict[:type],
      master_change: conflict[:master_change],
      slave_change: conflict[:slave_change],
      resolution: resolution[:action],
      reason: resolution[:reason],
      resolved_at: Time.current
    )
  rescue => e
    Rails.logger.error "Failed to log conflict resolution: #{e.message}"
  end
end 