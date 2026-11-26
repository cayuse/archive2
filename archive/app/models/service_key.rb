# A key for a program that works on the archive, as opposed to a person's login. It opens exactly
# one scope ("analysis": the sound-analysis API under /api/v1/analysis) and nothing else in the
# app. The key itself is shown once, when issued; the database keeps only its SHA-256 digest, so
# a copy of the database does not give anyone a working key.
#
#   rake "analysis:key[my-pc]"      issue      rake analysis:keys      list
#   rake "analysis:revoke[my-pc]"   revoke
class ServiceKey < ApplicationRecord
  SCOPES = %w[analysis].freeze

  validates :name, presence: true, uniqueness: true
  validates :scope, inclusion: { in: SCOPES }

  scope :active, -> { where(revoked_at: nil) }

  def self.digest(token) = Digest::SHA256.hexdigest(token.to_s)

  # Returns [key, token]. The token cannot be recovered later.
  def self.issue!(name:, scope:)
    token = "arc_#{scope}_#{SecureRandom.urlsafe_base64(32)}"
    [ create!(name: name, scope: scope, token_digest: digest(token), token_hint: token.last(4)), token ]
  end

  def self.authenticate(token, scope:)
    return nil if token.blank?
    active.find_by(token_digest: digest(token), scope: scope)
  end

  def revoke! = update!(revoked_at: Time.current)

  def used!(ip:, wrote: 0)
    self.class.where(id: id).update_all([ "last_used_at = ?, last_used_ip = ?, writes_count = writes_count + ?", Time.current, ip.to_s.first(64), wrote ])
  end
end
