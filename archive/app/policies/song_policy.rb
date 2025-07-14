class SongPolicy < ApplicationPolicy
  # Inherits from ApplicationPolicy which allows:
  # - Everyone can view (index?, show?)
  # - Only moderators/admins can create/update
  # - Only admins can destroy

  # Additional methods for song-specific permissions
  def upload_audio?
    user&.moderator? || user&.admin?
  end

  def download_audio?
    true # Everyone can download audio files
  end

  def manage_metadata?
    user&.moderator? || user&.admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.all
    end
  end
end
