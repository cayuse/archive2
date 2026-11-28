# Library quality (admins): copies merged onto a better one, each with the way back, and the songs
# still wanted because their only copy is broken or poor. See docs/reference/LIBRARY_QUALITY.md.
class LibraryQualityController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin!

  WANTED_KINDS = { "broken" => "Broken", "flawed" => "Flawed", "low_fidelity" => "Low fidelity" }.freeze

  def index
    @kind = WANTED_KINDS.key?(params[:kind]) ? params[:kind] : "broken"
    @counts = {
      measured: SongMeasurement.count, songs: Song.count, hidden: Song.hidden.count,
      wanted: SongIssue.wanted.group(:kind).count
    }
    @merges = SongMerge.order(created_at: :desc).includes(song: [ :album, :measurement ], canonical_song: [ :album, :measurement ]).limit(100)
    @wanted = SongIssue.wanted.where(kind: @kind).includes(song: [ :album, :measurement ])
                       .joins("LEFT JOIN (SELECT song_id, count(*) AS plays FROM ajb_played_songs GROUP BY song_id) p ON p.song_id = song_issues.song_id")
                       .order(Arel.sql("coalesce(p.plays, 0) DESC, song_issues.created_at DESC")).limit(200)
  end

  def restore
    merge = SongMerge.find(params[:id])
    SongMerger.new(source: "manual").restore!(merge)
    redirect_to library_quality_path, notice: "Restored: #{merge.song.title} plays again as its own copy."
  rescue ArgumentError => e
    redirect_to library_quality_path, alert: e.message
  end

  private

  def require_admin!
    redirect_to root_path, alert: "Admins only." unless current_user.admin?
  end
end
