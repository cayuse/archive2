class ThemesController < ApplicationController
  # No authentication required for theme assets - they're public
  skip_before_action :authenticate_user!, raise: false
  
  def css
    theme = Theme.find_by(name: params[:theme])
    
    if theme
      css_content = theme.generate_css
      render plain: css_content, content_type: 'text/css'
    else
      render plain: '/* Theme not found */', content_type: 'text/css', status: :not_found
    end
  end

  def asset
    theme = Theme.find_by(name: params[:theme])
    asset_type = params[:asset_type]
    filename = params[:filename]
    
    if theme && asset_type && filename
      asset = theme.get_asset(asset_type, filename)
      
      if asset&.file&.attached?
        redirect_to asset.file
      else
        render plain: 'Asset not found', status: :not_found
      end
    else
      render plain: 'Invalid asset request', status: :bad_request
    end
  end
end 