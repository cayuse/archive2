class ArchiveUser < ApplicationRecord
  self.table_name = 'users'
  
  def readonly?
    true
  end
  
  has_many :songs, class_name: 'ArchiveSong', foreign_key: 'user_id'
  
  def display_name
    name.presence || "Unknown User"
  end
end 