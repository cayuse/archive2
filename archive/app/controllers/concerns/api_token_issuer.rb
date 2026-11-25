# Mints the short-lived API token a logged-in user's browser page uses to call /api/v1 (the same
# token format the API's own login returns; see Api::V1::JukeboxesController#authenticate_api_user!).
module ApiTokenIssuer
  extend ActiveSupport::Concern

  private

  def api_token_for(user, expires_in: 2.days)
    payload = { user_id: user.id, email: user.email, role: user.role,
                exp: expires_in.from_now.to_i, iat: Time.current.to_i, iss: "archive-api" }
    encryptor = ActiveSupport::MessageEncryptor.new(Rails.application.secret_key_base[0, 32])
    Base64.urlsafe_encode64(encryptor.encrypt_and_sign(payload.to_json))
  end
end
