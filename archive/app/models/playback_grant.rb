# "This user may start local playback on this archive node." Admin-assigned (see
# UsersController). The tools only appear when such a grant exists AND the client
# is on the node's LAN; every start is also validated server-side.
class PlaybackGrant < ApplicationRecord
  belongs_to :user
  belongs_to :archive_node

  validates :user_id, uniqueness: { scope: :archive_node_id }
end
