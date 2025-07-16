class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  
  # Include Pundit authorization
  include PunditAuthorization
  
  # Error handling
  rescue_from ActiveRecord::RecordNotFound, with: :handle_record_not_found
  
  # Authentication helpers
  def current_user
    @current_user ||= User.find(session[:user_id]) if session[:user_id]
  end
  
  def authenticate_user!
    redirect_to login_path unless current_user
  end
  
  helper_method :current_user
  
  private
  
  def handle_record_not_found(exception)
    # Log the error for debugging
    Rails.logger.warn "Record not found: #{exception.message}"
    
    # Redirect to appropriate page with user-friendly message
    redirect_to root_path, alert: "The requested item could not be found."
  end
end
