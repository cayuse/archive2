class Api::V1::AuthController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_api_user!, only: [:verify, :logout]

  def login
    user = User.find_by(email: params[:email])
    
    if user&.authenticate(params[:password])
      # Generate API token
      api_token = generate_api_token(user)
      
      render json: {
        success: true,
        message: "Authentication successful",
        api_token: api_token,
        user: {
          id: user.id,
          name: user.name,
          email: user.email,
          role: user.role
        }
      }, status: :ok
    else
      render json: {
        success: false,
        message: "Invalid email or password"
      }, status: :unauthorized
    end
  end

  def logout
    # In a real implementation, you might want to invalidate the token
    # For now, we'll just return a success message
    render json: {
      success: true,
      message: "Logged out successfully"
    }, status: :ok
  end

  def verify
    # This endpoint is used to verify API tokens
    render json: {
      success: true,
      message: "API token is valid",
      user: {
        id: @current_api_user.id,
        name: @current_api_user.name,
        email: @current_api_user.email,
        role: @current_api_user.role
      }
    }, status: :ok
  end

  private

  def generate_api_token(user)
    # In a production app, you'd want to use a proper JWT library
    # For now, we'll create a simple token
    payload = {
      user_id: user.id,
      email: user.email,
      role: user.role,
      exp: 30.days.from_now.to_i
    }
    
    # Simple base64 encoding (in production, use proper JWT)
    Base64.urlsafe_encode64(payload.to_json)
  end

  def authenticate_api_user!
    token = extract_token_from_header
    
    if token.blank?
      render json: { success: false, message: "Missing API token" }, status: :unauthorized
      return
    end

    begin
      # Decode the token
      payload = JSON.parse(Base64.urlsafe_decode64(token))
      
      # Check if token is expired
      if payload['exp'] && Time.current.to_i > payload['exp']
        render json: { success: false, message: "API token expired" }, status: :unauthorized
        return
      end
      
      # Find the user
      @current_api_user = User.find(payload['user_id'])
      
      unless @current_api_user
        render json: { success: false, message: "Invalid API token" }, status: :unauthorized
        return
      end
      
    rescue => e
      render json: { success: false, message: "Invalid API token" }, status: :unauthorized
      return
    end
  end

  def extract_token_from_header
    auth_header = request.headers['Authorization']
    return nil unless auth_header
    
    # Extract token from "Bearer <token>" format
    token = auth_header.gsub(/^Bearer\s+/, '')
    token.presence
  end
end 