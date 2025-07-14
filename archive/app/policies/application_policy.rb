# frozen_string_literal: true

class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index?
    # Everyone can view lists
    true
  end

  def show?
    # Everyone can view individual records
    true
  end

  def create?
    # Only moderators and admins can create content
    user&.moderator? || user&.admin?
  end

  def new?
    create?
  end

  def update?
    # Only moderators and admins can update content
    user&.moderator? || user&.admin?
  end

  def edit?
    update?
  end

  def destroy?
    # Only admins can destroy content
    user&.admin?
  end

  class Scope
    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      # By default, show all records
      scope.all
    end

    private

    attr_reader :user, :scope
  end
end
