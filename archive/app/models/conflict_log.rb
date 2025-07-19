class ConflictLog < ApplicationRecord
  validates :conflict_type, presence: true
  validates :resolution, presence: true
  validates :resolved_at, presence: true

  scope :recent, -> { order(resolved_at: :desc) }
  scope :by_type, ->(type) { where(conflict_type: type) }
  scope :since, ->(time) { where('resolved_at > ?', time) }

  # Instance methods
  def conflict_summary
    "#{conflict_type} - #{resolution} - #{reason}"
  end

  def master_table
    master_change&.dig('table')
  end

  def master_record_id
    master_change&.dig('record_id')
  end

  def slave_table
    slave_change&.dig('table')
  end

  def slave_record_id
    slave_change&.dig('record_id')
  end
end 