# A user's radio stations and the page that tunes one. The pages are shells: they load and change
# everything through /api/v1/jukeboxes, using a token minted here. A station is a Station record;
# the pages address it by the jukebox that plays it on this node (Station#runtime!).
class StationsController < ApplicationController
  include ApiTokenIssuer

  before_action :authenticate_user!
  before_action :require_host!

  def index
    Jukebox.station_for(current_user)
    @stations = Jukebox.stations_for(current_user)
    @playlists = Playlist.where("is_public = TRUE OR user_id = ?", current_user.id).order(:name)
    @api_token = api_token_for(current_user)
  end

  def show
    # by the id of the station's jukebox (what the pages link to) or of the Station itself
    @station = Jukebox.stations_for(current_user).find { |j| j.id == params[:id] || j.station_id == params[:id] }
    return redirect_to stations_path, alert: "That station does not exist." unless @station
    @api_token = api_token_for(current_user)
  end

  private

  def require_host!
    return if current_user&.can_host_jukebox?
    redirect_to root_path, alert: "Stations need the DJ, moderator, or admin role."
  end
end
