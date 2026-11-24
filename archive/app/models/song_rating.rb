# A user's thumbs up (1) or thumbs down (-1) on a song. Radio uses these to learn their taste.
class SongRating < ApplicationRecord
  belongs_to :user
  belongs_to :song

  validates :value, inclusion: { in: [ 1, -1 ] }
  validates :song_id, uniqueness: { scope: :user_id }

  # value 1 / -1 sets the rating, 0 clears it. Returns the stored value (0 when cleared).
  def self.rate!(user:, song:, value:)
    value = value.to_i
    if value.zero?
      where(user_id: user.id, song_id: song.id).delete_all
      return 0
    end
    rating = find_or_initialize_by(user_id: user.id, song_id: song.id)
    rating.update!(value: value.positive? ? 1 : -1)
    rating.value
  end
end
