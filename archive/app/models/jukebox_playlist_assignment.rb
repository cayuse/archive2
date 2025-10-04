class JukeboxPlaylistAssignment < ApplicationRecord
  self.table_name = 'jukebox_playlist_assignments'
  
  belongs_to :jukebox
  belongs_to :playlist

  validates :jukebox_id, presence: true
  validates :playlist_id, presence: true
  validates :weight, presence: true, numericality: { greater_than: 0 }
  validates :jukebox_id, uniqueness: { scope: :playlist_id }

  scope :enabled, -> { where(enabled: true) }
  scope :ordered, -> { order(:weight, :created_at) }

  def disable!
    update!(enabled: false)
  end

  def enable!
    update!(enabled: true)
  end
end
