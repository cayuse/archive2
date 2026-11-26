# Decides whether to offer "play on this archive's speakers" to the current user,
# and guards starting it. Gated on the permission grant only (an admin decides who
# may drive local playback here); we deliberately do NOT gate on the client being
# on the LAN -- remote control, including a remote Stop, is useful and this is a
# handful of users. Every start/stop is still validated here, so a hidden-but-
# forged request is refused.
module LocalPlayback
  extend ActiveSupport::Concern

  included do
    helper_method :current_archive, :local_playback_available?
  end

  # The Archive row this process runs as.
  def current_archive
    @current_archive ||= ArchiveNode.current
  end

  # Should the current user be offered local playback here?
  def local_playback_available?(user = current_user, archive = current_archive)
    user.present? && archive&.local_playback? && user.can_play_on?(archive)
  end

  # Guard for an action that starts/controls local playback.
  def authorize_local_playback!
    return if local_playback_available?
    respond_to do |f|
      f.json { render json: { error: "Local playback is not available to you here." }, status: :forbidden }
      f.html { head :forbidden }
    end
  end
end
