class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  
  include Pundit::Authorization
  
  # Simple current_user method - returns nil for non-logged-in users
  def current_user
    nil
  end
  
  # Override Pundit's user method to use current_user
  def pundit_user
    current_user
  end
end
