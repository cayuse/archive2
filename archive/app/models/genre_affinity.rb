# "Adjacent" genres, learned from the audio: songs tagged +genre+ often sound like songs tagged
# +related_genre+ (score = how many times more often than chance). Rebuilt by library:import_audio.
class GenreAffinity < ApplicationRecord
  belongs_to :genre
  belongs_to :related_genre, class_name: "Genre"
end
