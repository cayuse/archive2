class AlbumPolicy < ApplicationPolicy
  # Inherits from ApplicationPolicy which allows:
  # - Everyone can view (index?, show?)
  # - Only moderators/admins can create/update
  # - Only admins can destroy

  # Additional methods for album-specific permissions
  def manage_songs?
    user&.moderator? || user&.admin?
  end

  def manage_genres?
    user&.moderator? || user&.admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.all
    end
  end
end
