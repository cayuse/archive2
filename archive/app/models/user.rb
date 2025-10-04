class User < ApplicationRecord
  # Authentication
  has_secure_password
  
  # Associations
  has_many :playlists, dependent: :destroy
  has_many :jukeboxes, foreign_key: :owner_id, dependent: :destroy

  # Enums
  enum :role, { user: 0, moderator: 1, admin: 2 }
  
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
  
  private
  
  def normalize_email
    self.email = email.downcase.strip if email.present?
  end
end 