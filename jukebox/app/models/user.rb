class User < ApplicationRecord
  # Authentication
  has_secure_password
  
  # Align with Archive enum mapping (integer column :role)
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
  scope :admins, -> { where(role: roles[:admin]) }
  
  # Instance methods
  def display_name
    name
  end
  
  def guest?
    false
  end
  
  private
  
  def normalize_email
    self.email = email.downcase.strip if email.present?
  end
end 