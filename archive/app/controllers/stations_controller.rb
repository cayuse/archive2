# A user's radio stations and the page that tunes one. The pages are shells: they load and change
# everything through /api/v1/jukeboxes (stations are jukeboxes), using a token minted here.
class StationsController < ApplicationController
  include ApiTokenIssuer

  before_action :authenticate_user!
  before_action :require_host!

  def index
    Jukebox.station_for(current_user)
    @stations = Jukebox.stations_for(current_user)
    @api_token = api_token_for(current_user)
  end

  def show
    @station = Jukebox.stations_for(current_user).find(params[:id])
    @api_token = api_token_for(current_user)
  rescue ActiveRecord::RecordNotFound
    redirect_to stations_path, alert: "That station does not exist."
  end

  private

  def require_host!
    return if current_user&.can_host_jukebox?
    redirect_to root_path, alert: "Stations need the DJ, moderator, or admin role."
  end
end
