class PlaylistsSong < ApplicationRecord
  # Associations with explicit UUID foreign key types
  belongs_to :playlist, foreign_key: :playlist_id, primary_key: :id
  belongs_to :song, foreign_key: :song_id, primary_key: :id

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
    
    # Get all songs in this playlist (excluding current song using composite key)
    # Use explicit SQL to avoid UUID association issues
    playlist_items = PlaylistsSong.where(playlist_id: playlist_id).where.not(
      playlist_id: playlist_id, 
      song_id: song_id
    ).ordered
    
    if new_position > position
      # Moving down - shift items between old and new position up
      playlist_items.where("position > ? AND position <= ?", position, new_position)
                   .update_all("position = position - 1")
    else
      # Moving up - shift items between new and old position down
      playlist_items.where("position >= ? AND position < ?", new_position, position)
                   .update_all("position = position + 1")
    end
    
    # Use raw SQL to avoid primary key issues
    PlaylistsSong.where(playlist_id: playlist_id, song_id: song_id)
                 .update_all(position: new_position)
  end
  
  private
  
  def renumber_playlist
    # Renumber all songs in the playlist to ensure sequential ordering
    # Since this table has no primary key, we need to use a more explicit approach
    # Use explicit SQL to avoid UUID association issues
    PlaylistsSong.where(playlist_id: playlist_id).ordered.each_with_index do |item, index|
      new_position = index + 1
      unless item.position == new_position
        # Use raw SQL to avoid primary key issues
        PlaylistsSong.where(playlist_id: item.playlist_id, song_id: item.song_id)
                     .update_all(position: new_position)
      end
    end
  end
end 