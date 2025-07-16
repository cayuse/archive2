class UserPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def create?
    true
  end

  def update?
    user == record || user&.admin?
  end

  def edit?
    update?
  end

  def destroy?
    user&.admin?
  end

  class Scope < Scope
    def resolve
      scope.all
    end
  end
end 