module ApplicationHelper
  def format_duration(seconds)
    return "0:00" unless seconds
    
    minutes = (seconds / 60).to_i
    remaining_seconds = (seconds % 60).to_i
    
    "#{minutes}:#{remaining_seconds.to_s.rjust(2, '0')}"
  end
end
