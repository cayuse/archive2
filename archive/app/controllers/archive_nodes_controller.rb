# Admin page for this archive node: whether it offers local (speaker) playback, what it is
# called, and the token its player daemon signs in with.
class ArchiveNodesController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin
  before_action { @node = ArchiveNode.current }

  def show
    @on_air = Jukebox.on_air
  end

  def update
    if @node.update(params.require(:archive_node).permit(:name, :local_playback, :player_url, :lan_cidr))
      Jukebox.where(server_playback: true).find_each(&:end_server_playback!) unless @node.local_playback?
      redirect_to archive_node_path, notice: "Saved."
    else
      @on_air = Jukebox.on_air
      render :show, status: :unprocessable_entity
    end
  end

  # A new token; the daemon's old one stops working at once.
  def regenerate_token
    @node.regenerate_player_token
    redirect_to archive_node_path, notice: "New player token made. Put it in the daemon's .env (NODE_TOKEN) and restart it."
  end

  private

  def require_admin
    return if current_user&.admin?
    flash[:error] = "Access denied. Admin privileges required."
    redirect_to root_path
  end
end
