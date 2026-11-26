class User < ApplicationRecord
  # Authentication
  has_secure_password
  
  # Associations
  has_many :playlists, dependent: :destroy
  has_many :station_feedbacks, dependent: :destroy
  has_many :jukeboxes, foreign_key: :owner_id, dependent: :destroy
  has_many :playback_grants, dependent: :destroy
  has_many :playback_nodes, through: :playback_grants, source: :archive_node

  # Enums.
  # NOTE: roles are capability-based (see the predicate methods below), not a
  # strict numeric hierarchy. `dj` is a lightweight role that can host AJB
  # jukeboxes but has no moderator powers — added at value 3 so existing
  # user/moderator/admin records (0/1/2) need no migration.
  enum :role, { user: 0, moderator: 1, admin: 2, dj: 3 }
  
  # Validations
  validates :email, presence: true, uniqueness: true, 
            format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true, length: { minimum: 2, maximum: 50 }
  validates :role, presence: true, inclusion: { in: roles.keys }
  
  # Callbacks
  before_validation :normalize_email
  
  # Scopes
  scope :active, -> { where.not(email: nil) }
  scope :admins, -> { where(role: :admin) }
  scope :moderators, -> { where(role: [:moderator, :admin]) }
  
  # Instance methods
  def display_name
    name
  end
  
  def admin?
    role == 'admin'
  end
  
  def moderator?
    role == 'moderator' || role == 'admin'
  end
  
  def user?
    role == 'user'
  end

  def dj?
    role == 'dj'
  end

  # Who may create/host AJB jukeboxes: DJs, moderators, and admins.
  def can_host_jukebox?
    dj? || moderator? || admin?
  end

  # May this user start local playback on the given archive node? (Granted by an
  # admin; the surfacing also requires the client to be on that archive's LAN.)
  def can_play_on?(node)
    node.present? && playback_grants.exists?(archive_node_id: node.id)
  end
  
  private
  
  def normalize_email
    self.email = email.downcase.strip if email.present?
  end
end 