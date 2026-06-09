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

  # Ordered, eager-loaded relation for the play-history views (paginate this).
  scope :history_for, ->(jukebox) {
    for_jukebox(jukebox).order(played_at: :desc).includes(song: [:artist, :album])
  }

  # JSON shape used by the player/guest play-history views.
  def history_payload
    {
      id: id,
      source: source,
      played_at: played_at&.iso8601,
      song: {
        id: song.id,
        title: song.title,
        artist: song.artist&.name,
        album: song.album&.title,
        duration: song.duration
      }
    }
  end

  # Instance methods
  def requested?
    source == 'requested'
  end

  def random?
    source == 'random'
  end
end
