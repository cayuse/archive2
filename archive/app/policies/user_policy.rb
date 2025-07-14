class UserPolicy < ApplicationPolicy
  # Users can view their own profile
  def show?
    user == record || super
  end

  # Users can update their own profile
  def update?
    user == record || super
  end

  def edit?
    update?
  end

  # Only admins can create/destroy users
  def create?
    user&.admin?
  end

  def destroy?
    user&.admin? && user != record # Can't delete yourself
  end

  # Only admins can manage user roles
  def manage_roles?
    user&.admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user&.admin?
        scope.all
      else
        scope.none # Regular users can't see other users
      end
    end
  end
end
