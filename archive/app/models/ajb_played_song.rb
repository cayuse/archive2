class AjbPlayedSong < ApplicationRecord
  belongs_to :jukebox
  belongs_to :song

  validates :jukebox_id, presence: true
  validates :song_id, presence: true
  validates :played_at, presence: true
  validates :source, presence: true, inclusion: { in: %w[random requested] }

  # Scopes
  scope :for_jukebox, ->(jukebox) { where(jukebox: jukebox) }
  scope :recent, ->(limit = 50) { order(played_at: :desc).limit(limit) }
  scope :by_source, ->(source) { where(source: source) }
  
  # Class methods
  def self.recently_played_for_jukebox(jukebox, limit = 50)
    for_jukebox(jukebox).recent(limit)
  end

  def self.recently_played_song_ids_for_jukebox(jukebox, limit = 50)
    recently_played_for_jukebox(jukebox, limit).pluck(:song_id)
  end

  # Instance methods
  def requested?
    source == 'requested'
  end

  def random?
    source == 'random'
  end
end
