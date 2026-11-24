# What the audio analysis heard in a song. The 0..1 dials are percentiles within the library
# (0.9 energy = more energetic than 90% of the archive), so they can be compared and steered by.
class SongAudioFeature < ApplicationRecord
  DIALS = %w[energy danceability happiness aggression acousticness electronic instrumental speech].freeze

  belongs_to :song

  validates :song_id, uniqueness: true
end
