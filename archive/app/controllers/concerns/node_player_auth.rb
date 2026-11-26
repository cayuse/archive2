# Recognises this node's player daemon (station/station.py). It presents the node's player token
# in X-Node-Token instead of logging in as a person, and acts for whichever jukebox has the
# speakers, on behalf of that jukebox's owner.
module NodePlayerAuth
  extend ActiveSupport::Concern

  private

  def node_player_request?
    given = request.headers["X-Node-Token"].to_s
    token = ArchiveNode.current.player_token.to_s
    given.present? && token.present? && ActiveSupport::SecurityUtils.secure_compare(given, token)
  end

  # The user a Bearer API token belongs to, or nil (same format as Api::V1::AuthController issues).
  def user_from_bearer_token
    token = request.headers["Authorization"].to_s.sub(/^Bearer\s+/, "")
    return nil if token.blank?
    encryptor = ActiveSupport::MessageEncryptor.new(Rails.application.secret_key_base[0, 32])
    payload = JSON.parse(encryptor.decrypt_and_verify(Base64.urlsafe_decode64(token)))
    return nil if payload["exp"] && Time.current.to_i > payload["exp"]
    User.find_by(id: payload["user_id"])
  rescue StandardError
    nil
  end
end
