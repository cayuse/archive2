# The audio embedding vector of a song (kept apart from the features because it is large).
class SongEmbedding < ApplicationRecord
  belongs_to :song

  validates :song_id, uniqueness: true
end
