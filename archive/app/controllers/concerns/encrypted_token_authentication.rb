module EncryptedTokenAuthentication
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_encrypted_token_user!
    # Declared after PunditAuthorization's handler, so it wins for API
    # controllers: token clients get JSON errors, not HTML redirects.
    rescue_from Pundit::NotAuthorizedError, with: :api_user_not_authorized
  end

  private

  # Pundit policies must evaluate against the token user, not the (absent)
  # session user, or token clients only ever see public records.
  def pundit_user
    @current_api_user || current_user
  end

  def api_user_not_authorized
    render json: { success: false, message: "Not authorized" }, status: :forbidden
  end

  def authenticate_encrypted_token_user!
    token = extract_token_from_header
    
    if token.blank?
      render json: { success: false, message: "Missing API token" }, status: :unauthorized
      return
    end

    begin
      # Decode from Base64
      decoded_token = Base64.urlsafe_decode64(token)
      
      # Decrypt with Rails secret key
      encryptor = ActiveSupport::MessageEncryptor.new(Rails.application.secret_key_base[0, 32])
      decrypted_payload = encryptor.decrypt_and_verify(decoded_token)
      
      # Parse JSON payload
      payload = JSON.parse(decrypted_payload)
      
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
      Rails.logger.error "Token decryption error: #{e.message}"
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
