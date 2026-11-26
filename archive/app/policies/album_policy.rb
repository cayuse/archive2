class AlbumPolicy < ApplicationPolicy
  # Only the scope and the manage_* rules below are used (the controllers call policy_scope).
  # The standard rules (show?, create?, ...) are inherited from ApplicationPolicy, which denies them.

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
