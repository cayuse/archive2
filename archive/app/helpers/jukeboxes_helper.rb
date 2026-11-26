module JukeboxesHelper
  AJB_SCRIPTS = Rails.root.join("public/javascripts/ajb")

  # A fingerprint of the jukebox pages' own scripts: it changes whenever any of them changes, so a
  # page always loads the scripts it was written for (it goes on every script URL), and the player
  # reports it with each diagnostic heartbeat, so the log says exactly which code a phone ran.
  # Computed per request (a few files; staging serves the live tree, so a cache would go stale).
  def ajb_build
    @ajb_build ||= begin
      files = Dir.glob(AJB_SCRIPTS.join("**/*.js").to_s).sort
      Digest::SHA256.hexdigest(files.map { |f| "#{f.delete_prefix(AJB_SCRIPTS.to_s)}\0#{File.read(f)}" }.join("\0"))[0, 10]
    end
  end
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
