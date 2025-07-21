class ThemesController < ApplicationController
  # Asset serving - no authentication required for public assets
  # We'll handle authentication manually in the actions
  
  # Asset serving - no authentication required
  def asset
    theme = Theme.find_by(name: params[:theme])
    return head :not_found unless theme
    
    asset = theme.asset_by_type_and_filename(params[:asset_type], params[:filename])
    return head :not_found unless asset
    
    send_data asset.file_data, 
              type: asset.content_type, 
              disposition: 'inline',
              filename: asset.filename
  end
  
  # CSS serving - no authentication required
  def css
    theme = Theme.find_by(name: params[:theme])
    return head :not_found unless theme
    
    # Add caching headers for better performance
    response.headers['Cache-Control'] = 'public, max-age=3600' # 1 hour cache
    
    render plain: theme.generate_css, content_type: 'text/css'
  end
end 