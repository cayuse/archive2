# A playlist a station draws on, by reference (edit the playlist and the station follows).
#   inspire  its songs set the station's sound; the station wanders beyond them
#   only     the station plays nothing but its songs
class StationPlaylist < ApplicationRecord
  MODES = %w[inspire only].freeze
  belongs_to :station
  belongs_to :playlist
  validates :mode, inclusion: { in: MODES }
end
