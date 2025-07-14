# frozen_string_literal: true

module PunditAuthorization
  extend ActiveSupport::Concern

  included do
    include Pundit::Authorization
    
    # Rescue from Pundit::NotAuthorizedError
    rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized
    
    # Add helper methods for common authorization checks
    helper_method :can_manage_content?
    helper_method :can_manage_users?
    helper_method :can_upload_audio?
  end

  private

  def user_not_authorized
    flash[:alert] = "You are not authorized to perform this action."
    redirect_back(fallback_location: root_path)
  end

  # Helper methods for views
  def can_manage_content?
    current_user&.moderator? || current_user&.admin?
  end

  def can_manage_users?
    current_user&.admin?
  end

  def can_upload_audio?
    current_user&.moderator? || current_user&.admin?
  end

  # Common authorization methods for controllers
  def require_moderator_or_admin
    unless current_user&.moderator? || current_user&.admin?
      flash[:alert] = "Moderator or admin access required."
      redirect_back(fallback_location: root_path)
    end
  end

  def require_admin
    unless current_user&.admin?
      flash[:alert] = "Admin access required."
      redirect_back(fallback_location: root_path)
    end
  end

  def require_authenticated_user
    unless current_user
      flash[:alert] = "Please log in to continue."
      redirect_back(fallback_location: root_path)
    end
  end
end 