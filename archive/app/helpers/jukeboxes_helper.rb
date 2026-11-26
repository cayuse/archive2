module JukeboxesHelper
  def status_color(status)
    case status
    when "active"
      "success"
    when "paused"
      "warning"
    when "ended"
      "danger"
    else
      "secondary"
    end
  end
  LOOPBACK_HOSTS = %w[localhost 127.0.0.1 ::1].freeze

  # The short guest link (/j/<slug>) that QR codes and "share this" fields show.
  # A phone can't follow a localhost link, so when the page is being viewed on
  # the machine running the server and AJB_LAN_HOST is set (the dev stacks set
  # it to the machine's network address), the link uses that address instead.
  def guest_join_url(jukebox)
    lan_host = ENV["AJB_LAN_HOST"].presence
    if lan_host && LOOPBACK_HOSTS.include?(request.host)
      short_guest_url(jukebox.session_id, host: lan_host, port: request.port)
    else
      short_guest_url(jukebox.session_id)
    end
  end
end
