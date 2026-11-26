# The archive's side of server-side playback on this node.
#
#   POST /api/v1/node_player/sync      the player daemon's poll: reports its state, acknowledges
#                                      commands, learns which jukebox has the speakers
#   POST /api/v1/node_player/command   a person with a playback grant sets the volume or a speaker
#
# The daemon authenticates with the node's player token (X-Node-Token). Without one configured it
# may poll as a person (Bearer token) who holds a playback grant, and is then only given that
# person's own jukebox.
class Api::V1::NodePlayerController < ApplicationController
  include NodePlayerAuth

  skip_before_action :verify_authenticity_token
  before_action :authenticate!

  def sync
    node = ArchiveNode.current
    state = params[:state].respond_to?(:to_unsafe_h) ? params[:state].to_unsafe_h.slice("outputs", "volume", "owntone_state", "error") : {}
    commands = node.player_checkin!(ack: params[:ack], state: state)
    jukebox = node.local_playback? ? Jukebox.on_air : nil
    jukebox = nil if @user && jukebox && jukebox.owner_id != @user.id
    render json: { success: true, node: { name: node.name, local_playback: node.local_playback? },
                   jukebox: jukebox && on_air_json(jukebox), commands: commands }
  end

  def command
    return render json: { success: false, message: "The player daemon uses sync" }, status: 403 unless @user
    node = ArchiveNode.current
    case params[:cmd].to_s
    when "volume"
      node.push_player_command!("volume", params[:value].to_i.clamp(0, 100))
    when "output"
      node.push_player_command!("output", { "id" => params[:id].to_s, "selected" => ActiveModel::Type::Boolean.new.cast(params[:selected]) == true })
    else
      return render json: { success: false, message: "Unknown command" }, status: 422
    end
    render json: { success: true }
  end

  private

  def authenticate!
    return if node_player_request?
    @user = user_from_bearer_token
    return render json: { success: false, message: "Missing or invalid token" }, status: :unauthorized unless @user
    node = ArchiveNode.current
    return if node.local_playback? && @user.can_play_on?(node)
    render json: { success: false, message: "Local playback is not available to you here." }, status: :forbidden
  end

  def on_air_json(jukebox)
    song, position = jukebox.server_resume
    jukebox.station_json.merge(
      resume: song && {
        position: position,
        song: { id: song.id, title: song.title, artist: song.artist&.name, album: song.album&.title, duration: song.duration,
                play_url: public_song_url(token: SongPlayToken.generate(song.id, expires_in: 12.hours)) }
      }
    )
  end
end
