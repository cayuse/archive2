module ApiAuthentication
  extend ActiveSupport::Concern

  private

  def authenticate_slave_request
    provided_key = request.headers['X-Signature']
    node_id = request.headers['X-Node-ID']
    
    return render_unauthorized unless provided_key.present? && node_id.present?

    # Find slave by node ID
    slave_key = SlaveKey.active.find_by(node_id: node_id)
    return render_unauthorized unless slave_key
    
    # Verify key without storing original
    return render_unauthorized unless slave_key.verify_key(provided_key)

    # Update last used timestamp
    slave_key.mark_used
    
    # Set current slave for the request
    @current_slave = slave_key
  end

  def authenticate_jukebox_request
    provided_key = request.headers['X-Signature']
    
    return render_unauthorized unless provided_key.present?

    # Find jukebox by key
    jukebox_key = JukeboxKey.active.find_by(key_hash: BCrypt::Password.create(provided_key))
    return render_unauthorized unless jukebox_key
    
    # Check if jukebox can access this archive
    current_archive_id = SystemSetting.archive_node_id
    return render_unauthorized unless jukebox_key.can_access_archive?(current_archive_id)

    # Update last used timestamp
    jukebox_key.mark_used
    
    # Set current jukebox for the request
    @current_jukebox = jukebox_key
  end

  def render_unauthorized
    render json: { 
      error: 'Unauthorized',
      message: 'Invalid or missing authentication credentials'
    }, status: :unauthorized
  end

  def render_forbidden
    render json: { 
      error: 'Forbidden',
      message: 'Access denied to this resource'
    }, status: :forbidden
  end
end 