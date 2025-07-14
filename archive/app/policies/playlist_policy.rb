class PlaylistPolicy < ApplicationPolicy
  # Anyone can view public playlists
  def show?
    record.public? || user == record.user || super
  end

  # Users can create their own playlists
  def create?
    user.present?
  end

  # Users can update their own playlists
  def update?
    user == record.user || super
  end

  def edit?
    update?
  end

  # Users can destroy their own playlists, admins can destroy any
  def destroy?
    user == record.user || user&.admin?
  end

  # Users can manage their own playlists
  def manage_songs?
    user == record.user || super
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user&.admin?
        scope.all
      elsif user
        # Show user's own playlists + public playlists
        scope.where(user: user).or(scope.where(is_public: true))
      else
        # Show only public playlists for guests
        scope.where(is_public: true)
      end
    end
  end
end
