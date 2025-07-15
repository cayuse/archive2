module SongsHelper
  def status_badge_class(status)
    case status
    when 'completed'
      'bg-success'
    when 'failed'
      'bg-danger'
    when 'needs_review'
      'bg-warning'
    when 'new'
      'bg-info'
    when 'pending'
      'bg-secondary'
    when 'processing'
      'bg-primary'
    else
      'bg-secondary'
    end
  end
  
  def format_duration(seconds)
    return '--:--' if seconds.blank?
    
    minutes = seconds / 60
    remaining_seconds = seconds % 60
    "#{minutes}:#{remaining_seconds.to_s.rjust(2, '0')}"
  end
end 