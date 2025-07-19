class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  
  include Pundit::Authorization
  
  helper_method :current_user, :logged_in?
  
  private
  
  def current_user
    @current_user ||= User.find(session[:user_id]) if session[:user_id]
  rescue ActiveRecord::RecordNotFound
    session[:user_id] = nil
  end
  
  def logged_in?
    !!current_user
  end
  
  def require_login
    unless logged_in?
      flash[:alert] = "Please log in to access this feature"
      redirect_to login_path
    end
  end
  
  def require_admin
    unless current_user&.admin?
      flash[:alert] = "Admin access required"
      redirect_to root_path
    end
  end
  
  # Override Pundit's user method to use current_user
  def pundit_user
    current_user
  end
end
