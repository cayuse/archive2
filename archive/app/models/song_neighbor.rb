# Precomputed "sounds like" links: for each song its nearest songs by audio embedding, best first.
class SongNeighbor < ApplicationRecord
  belongs_to :song
  belongs_to :neighbor, class_name: "Song"
end
