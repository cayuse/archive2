# One artist credited on a song. A song keeps its main artist in songs.artist_id;
# this table lists every credited artist (main and featured) in credit order.
class SongArtistCredit < ApplicationRecord
  belongs_to :song
  belongs_to :artist

  validates :artist_id, uniqueness: { scope: :song_id }
end
