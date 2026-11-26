class BulkOperationsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_bulk_operations!

  UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  def index
    # Show bulk operations dashboard
  end

  def export_csv
    songs = Song.includes(:artist, :album, :genre).all
    csv_data = generate_csv(songs)

    send_data csv_data,
              filename: "songs_export_#{Date.current}.csv",
              type: "text/csv"
  end

  # Song ids are UUIDs, separated by commas, spaces or new lines.
  def bulk_delete
    entries = params[:song_ids].to_s.split(/[\s,]+/).reject(&:blank?).uniq
    ids, invalid = entries.partition { |id| id.match?(UUID) }

    if entries.empty?
      flash[:alert] = "Please enter the IDs of the songs to delete"
      redirect_to bulk_operations_path
      return
    end

    songs = Song.where(id: ids).to_a
    errors = invalid.map { |id| "#{id.truncate(40)} is not a song ID" }
    errors += (ids.map(&:downcase) - songs.map(&:id)).map { |id| "Song #{id} not found" }
    destroyed_count = 0
    songs.each do |song|
      if song.destroy
        destroyed_count += 1
      else
        errors << "Could not delete song #{song.id}"
      end
    end

    if errors.any?
      flash[:alert] = "Deleted #{destroyed_count} songs. Errors: #{errors.join(', ')}"
    else
      flash[:notice] = "Successfully deleted #{destroyed_count} songs"
    end

    redirect_to bulk_operations_path
  end

  private

  def authorize_bulk_operations!
    unless current_user&.moderator?
      flash[:alert] = "You don't have permission to perform bulk operations"
      redirect_to root_path
    end
  end

  def generate_csv(songs)
    require "csv"

    CSV.generate do |csv|
      csv << [ "id", "title", "track_number", "duration", "file_format", "file_size",
              "artist_name", "album_title", "album_release_date", "genre_name",
              "created_at", "updated_at" ]

      songs.each do |song|
        csv << [
          song.id,
          song.title,
          song.track_number,
          song.duration,
          song.file_format,
          song.file_size,
          song.artist&.name,
          song.album&.title,
          song.album&.release_date,
          song.genre&.name,
          song.created_at,
          song.updated_at
        ]
      end
    end
  end
end
