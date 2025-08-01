class SongPolicy < ApplicationPolicy
  # Inherits from ApplicationPolicy which allows:
  # - Everyone can view (index?, show?)
  # - Only moderators/admins can create/update
  # - Only admins can destroy

  # Override show? to allow everyone to view songs
  def show?
    true
  end

  # Additional methods for song-specific permissions
  def upload?
    user&.moderator? || user&.admin?
  end

  def upload_audio?
    user&.moderator? || user&.admin?
  end

  def download_audio?
    true # Everyone can download audio files
  end

  def manage_metadata?
    user&.moderator? || user&.admin?
  end

  def maintenance?
    user&.moderator? || user&.admin?
  end

  def bulk_update?
    user&.moderator? || user&.admin?
  end

  def destroy?
    user&.admin?
  end

  def edit?
    user&.moderator? || user&.admin?
  end

  def update?
    user&.moderator? || user&.admin?
  end

  def create?
    user&.moderator? || user&.admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.all
    end
  end
end
