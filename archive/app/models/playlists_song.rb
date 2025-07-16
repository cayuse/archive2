class PlaylistsSong < ApplicationRecord
  # Associations
  belongs_to :playlist
  belongs_to :song

  # Validations
  validates :playlist, presence: true
  validates :song, presence: true
  validates :position, numericality: { only_integer: true, greater_than: 0 }, allow_blank: true

  # Scopes
  scope :ordered, -> { order(:position) }
  
  # Callbacks
  after_save :renumber_playlist, if: :saved_change_to_position?
  after_destroy :renumber_playlist
  
  # Instance methods
  def reorder_to_position(new_position)
    return if new_position == position
    
    # Get all songs in this playlist
    playlist_items = playlist.playlists_songs.where.not(id: id).ordered
    
    if new_position > position
      # Moving down - shift items between old and new position up
      playlist_items.where("position > ? AND position <= ?", position, new_position)
                   .update_all("position = position - 1")
    else
      # Moving up - shift items between new and old position down
      playlist_items.where("position >= ? AND position < ?", new_position, position)
                   .update_all("position = position + 1")
    end
    
    update!(position: new_position)
  end
  
  private
  
  def renumber_playlist
    # Renumber all songs in the playlist to ensure sequential ordering
    playlist.playlists_songs.ordered.each_with_index do |item, index|
      item.update_column(:position, index + 1) unless item.position == index + 1
    end
  end
end 