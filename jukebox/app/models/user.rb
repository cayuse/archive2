class User < ApplicationRecord
  # Authentication
  has_secure_password
  
  # Validations
  validates :email, presence: true, uniqueness: true, 
            format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true, length: { minimum: 2, maximum: 50 }
  validates :role, presence: true, inclusion: { in: %w[admin] }
  
  # Callbacks
  before_validation :normalize_email
  
  # Scopes
  scope :active, -> { where.not(email: nil) }
  scope :admins, -> { where(role: 'admin') }
  
  # Instance methods
  def display_name
    name
  end
  
  def admin?
    role == 'admin'
  end
  
  def guest?
    false
  end
  
  private
  
  def normalize_email
    self.email = email.downcase.strip if email.present?
  end
end 