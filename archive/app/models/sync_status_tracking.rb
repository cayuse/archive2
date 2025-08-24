class SyncStatusTracking < ApplicationRecord
  validates :sync_type, presence: true, inclusion: { in: %w[database file initial] }
  validates :status, presence: true, inclusion: { in: %w[success failed in_progress] }
  
  scope :recent_failures, -> { where(status: 'failed').where('last_attempt_at > ?', 1.hour.ago) }
  scope :pending_retries, -> { where(status: 'failed').where('next_attempt_at <= ?', Time.current) }
  scope :by_type, ->(type) { where(sync_type: type) }
  scope :by_target, ->(node_id) { where(target_node_id: node_id) }
  
  # Mark sync as in progress
  def mark_in_progress!
    update!(
      status: 'in_progress',
      last_attempt_at: Time.current,
      attempt_count: attempt_count + 1
    )
  end
  
  # Mark sync as successful
  def mark_successful!(metadata = {})
    update!(
      status: 'success',
      last_success_at: Time.current,
      error_message: nil,
      sync_metadata: metadata
    )
  end
  
  # Mark sync as failed with error
  def mark_failed!(error_message, retry_after = nil)
    next_attempt = retry_after || calculate_next_retry_time
    
    update!(
      status: 'failed',
      error_message: error_message,
      next_attempt_at: next_attempt
    )
  end
  
  # Check if sync should be retried
  def should_retry?
    status == 'failed' && next_attempt_at <= Time.current
  end
  
  # Get time since last successful sync
  def time_since_last_success
    return nil unless last_success_at
    Time.current - last_success_at
  end
  
  # Check if sync is healthy (recent success)
  def healthy?
    return false unless last_success_at
    time_since_last_success < 1.hour
  end
  
  private
  
  def calculate_next_retry_time
    # Exponential backoff: 1min, 2min, 4min, 8min, 16min, 30min max
    backoff_minutes = [2**(attempt_count - 1), 30].min
    Time.current + backoff_minutes.minutes
  end
end
