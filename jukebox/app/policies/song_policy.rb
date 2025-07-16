class SongPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def create?
    user.present?
  end

  def update?
    user.present?
  end

  def edit?
    user.present?
  end

  def destroy?
    user&.admin?
  end

  def upload_audio?
    user.present?
  end

  def retry_processing?
    user.present?
  end

  class Scope < Scope
    def resolve
      scope.all
    end
  end
end 