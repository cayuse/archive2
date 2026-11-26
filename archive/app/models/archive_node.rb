# A peer in the archive mesh: this node, plus any master/clone a user can start
# local playback on. Identified by node_id (system_settings 'archive_node_id').
# UUID-keyed and node-agnostic so rows can propagate to peers later; no sync here.
# (Named ArchiveNode, not Archive, because the app itself is `module Archive`.)
class ArchiveNode < ApplicationRecord
  has_many :playback_grants, dependent: :destroy
  has_many :users, through: :playback_grants

  validates :node_id, presence: true, uniqueness: true
  validates :name, presence: true

  scope :offering_local, -> { where(local_playback: true) }

  # The row for the archive node this process is running as, created on first use.
  def self.current
    node = SystemSetting.archive_node_id
    find_or_create_by(node_id: node) { |n| n.name = node }
  end

  def self_node?
    node_id == SystemSetting.archive_node_id
  end
end
