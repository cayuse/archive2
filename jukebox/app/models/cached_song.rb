class JukeboxCachedSong < ApplicationRecord
  self.table_name = 'jukebox_cached_songs'
  
  # Relationships
  belongs_to :archive_song, class_name: 'ArchiveSong', foreign_key: 'song_id'
  
  # Validations
  validates :song_id, presence: true, uniqueness: true
  validates :file_path, presence: true
  validates :file_size, presence: true, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: %w[downloading completed failed] }
  
  # Scopes
  scope :completed, -> { where(status: 'completed') }
  scope :failed, -> { where(status: 'failed') }
  scope :downloading, -> { where(status: 'downloading') }
  scope :available, -> { completed.where('file_size > 0') }
  
  # Callbacks
  before_create :set_default_status
  
  # File management
  def file_exists?
    File.exist?(file_path) && File.size(file_path) == file_size
  end
  
  def delete_file
    File.delete(file_path) if File.exist?(file_path)
    destroy
  end
  
  def self.cache_directory
    Rails.root.join('storage', 'cached_songs')
  end
  
  def self.ensure_cache_directory
    FileUtils.mkdir_p(cache_directory) unless Dir.exist?(cache_directory)
  end
  
  def self.find_or_create_for_song(song)
    find_or_create_by(song_id: song.id) do |cached_song|
      cached_song.file_path = generate_file_path(song)
      cached_song.status = 'downloading'
    end
  end
  
  def self.generate_file_path(song)
    ensure_cache_directory
    extension = File.extname(song.audio_file.filename.to_s) || '.mp3'
    filename = "#{song.id}_#{song.title.parameterize}#{extension}"
    cache_directory.join(filename)
  end
  
  def mark_as_completed!
    update!(
      status: 'completed',
      downloaded_at: Time.current,
      file_size: File.size(file_path)
    )
  end
  
  def mark_as_failed!
    update!(status: 'failed', downloaded_at: Time.current)
  end
  
  private
  
  def set_default_status
    self.status ||= 'downloading'
  end
end 