module JukeboxesHelper
  def status_color(status)
    case status
    when 'active'
      'success'
    when 'paused'
      'warning'
    when 'ended'
      'danger'
    else
      'secondary'
    end
  end
end
