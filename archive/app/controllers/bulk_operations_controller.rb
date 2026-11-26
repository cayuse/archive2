class BulkOperationsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_bulk_operations!

  UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  def index
    # Show bulk operations dashboard
  end

  def upload_csv
    if params[:file].blank?
      flash[:alert] = "Please select a file to upload"
      redirect_to bulk_operations_path
      return
    end

    file = params[:file]

    unless file.content_type.to_s.include?("csv") || File.extname(file.original_filename.to_s).casecmp?(".csv")
      flash[:alert] = "Please upload a CSV file"
      redirect_to bulk_operations_path
      return
    end

    begin
      # Process CSV upload
      result = process_csv_upload(file)

      if result[:success]
        flash[:notice] = "Imported #{result[:created_count]} songs."
        if result[:errors].any?
          rows = result[:errors].first(10).map { |e| "row #{e[:row]}: #{Array(e[:errors] || e[:error]).join(', ')}" }
          flash[:alert] = "#{result[:errors].length} rows were skipped (#{rows.join('; ')})"
        end
      else
        flash[:alert] = "Import failed: #{result[:error]}"
      end
    rescue => e
      flash[:alert] = "Error processing file: #{e.message}"
    end

    redirect_to bulk_operations_path
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

  def process_csv_upload(file)
    require "csv"

    csv_data = CSV.parse(file.read, headers: true)
    created_songs = []
    errors = []

    csv_data.each_with_index do |row, index|
      begin
        song_data = {
          title: row["title"],
          track_number: row["track_number"],
          duration: row["duration"],
          file_format: row["file_format"],
          file_size: row["file_size"],
          artist_name: row["artist_name"],
          album_title: row["album_title"],
          album_release_date: row["album_release_date"],
          genre_name: row["genre_name"]
        }

        song = create_song_from_data(song_data)
        if song.persisted?
          created_songs << song
        else
          errors << { row: index + 2, errors: song.errors.full_messages }
        end
      rescue => e
        errors << { row: index + 2, error: e.message }
      end
    end

    {
      success: true,
      created_count: created_songs.length,
      errors: errors
    }
  rescue => e
    {
      success: false,
      error: e.message
    }
  end

  # A song record without an audio file: the row's details, with its artist, album and genre
  # found by name or created.
  def create_song_from_data(data)
    data = data.transform_values { |v| v.to_s.strip.presence }
    song = Song.new(data.slice(:title, :track_number, :duration, :file_format, :file_size).merge(user: current_user))
    if data[:title].nil?
      song.errors.add(:title, "can't be blank")
      return song
    end
    return song unless song.valid?

    song.artist = Artist.find_or_create_by!(name: data[:artist_name]) if data[:artist_name]
    if data[:album_title] && song.artist
      song.album = Album.find_or_create_by!(title: data[:album_title], artist: song.artist) do |a|
        a.release_date = data[:album_release_date]
      end
    end
    song.genre = Genre.find_or_create_by!(name: data[:genre_name]) if data[:genre_name]
    song.save
    song
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
