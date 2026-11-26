require "ipaddr"

# Decides whether to offer "play locally on this archive" to the current user,
# and guards the start of it. The button appears only when: this archive offers
# local playback, the user holds a grant for it, AND the client is on the LAN
# (playing music in a home you are away from is pointless). Every start is also
# validated here, so a hidden-but-forged request still gets refused.
module LocalPlayback
  extend ActiveSupport::Concern

  # Ranges treated as "local" when an archive sets no explicit lan_cidr.
  PRIVATE_RANGES = %w[10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16
                      127.0.0.0/8 ::1/128 fc00::/7 fe80::/10].map { |c| IPAddr.new(c) }.freeze

  included do
    helper_method :current_archive, :client_local?, :local_playback_available?
  end

  # The Archive row this process runs as.
  def current_archive
    @current_archive ||= ArchiveNode.current
  end

  # Is the requester on this archive's local network?
  def client_local?(archive = current_archive, req = request)
    ip = IPAddr.new(req.remote_ip)
    if archive&.lan_cidr.present?
      archive.lan_cidr.split(",").any? { |c| IPAddr.new(c.strip).include?(ip) rescue false }
    else
      PRIVATE_RANGES.any? { |r| r.include?(ip) }
    end
  rescue IPAddr::Error
    false
  end

  # Should the current user be offered local playback here right now?
  def local_playback_available?(user = current_user, archive = current_archive)
    user.present? && archive&.local_playback? && user.can_play_on?(archive) && client_local?(archive)
  end

  # Guard for the action that actually starts local playback.
  def authorize_local_playback!
    return if local_playback_available?
    respond_to do |f|
      f.json { render json: { error: "Local playback is not available to you here." }, status: :forbidden }
      f.html { head :forbidden }
    end
  end
end
