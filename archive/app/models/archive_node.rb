# A peer in the archive mesh: this node, plus any master/clone a user can start
# local playback on. Identified by node_id (system_settings 'archive_node_id').
# UUID-keyed and node-agnostic so rows can propagate to peers later; no sync here.
# (Named ArchiveNode, not Archive, because the app itself is `module Archive`.)
#
# A node that offers local playback has a player daemon (station/station.py) feeding its speakers.
# The daemon polls the archive (Api::V1::NodePlayerController#sync) with the node's player_token;
# the archive answers with the jukebox that has the speakers and any one-shot commands.
class ArchiveNode < ApplicationRecord
  has_many :playback_grants, dependent: :destroy
  has_many :users, through: :playback_grants

  has_secure_token :player_token

  validates :node_id, presence: true, uniqueness: true
  validates :name, presence: true

  scope :offering_local, -> { where(local_playback: true) }

  PLAYER_ONLINE_WINDOW = 15.seconds
  COMMAND_TTL = 30.seconds      # a command the daemon did not collect in time is dropped, not replayed later
  PLAYER_COMMANDS = %w[skip volume output retune].freeze

  # The row for the archive node this process is running as, created on first use.
  def self.current
    node = SystemSetting.archive_node_id
    find_or_create_by(node_id: node) { |n| n.name = node }
  end

  def self_node?
    node_id == SystemSetting.archive_node_id
  end

  # Is the player daemon polling?
  def player_online?
    player_seen_at.present? && player_seen_at > PLAYER_ONLINE_WINDOW.ago
  end

  def push_player_command!(cmd, value = nil)
    raise ArgumentError, "unknown player command #{cmd}" unless PLAYER_COMMANDS.include?(cmd.to_s)
    with_lock do
      seq = player_command_seq + 1
      fresh = pending_player_commands + [ { "seq" => seq, "cmd" => cmd.to_s, "value" => value, "at" => Time.current.to_f } ]
      update!(player_command_seq: seq, player_commands: fresh.last(20))
    end
  end

  def pending_player_commands
    cutoff = COMMAND_TTL.ago.to_f
    Array(player_commands).select { |c| c["at"].to_f >= cutoff }
  end

  # The daemon checked in: forget the commands it has carried out, remember what it reports,
  # and hand back the commands still waiting.
  def player_checkin!(ack:, state:)
    with_lock do
      waiting = pending_player_commands.select { |c| c["seq"].to_i > ack.to_i }
      attrs = {}
      attrs[:player_commands] = waiting if waiting != player_commands
      attrs[:player_state] = state if state.present? && state != player_state
      attrs[:player_seen_at] = Time.current if attrs.any? || player_seen_at.nil? || player_seen_at < 5.seconds.ago
      update_columns(attrs) if attrs.any?
      waiting
    end
  end
end
