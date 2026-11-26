# The drop box: a page that takes dropped files, folders and archives and shows what became of
# each one. The browser sends the files one by one into an IntakeBatch; the intake worker
# (rake intake:work) deals with the batch once the browser says it has sent everything.
class IntakeController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_drop!
  before_action :set_batch, only: [ :show, :upload, :finish ]

  def index
    @batches = visible_batches.recent.limit(30).to_a
    @counts = IntakeItem.where(intake_batch_id: @batches.map(&:id)).group(:intake_batch_id, :status).count
    @awaiting_analysis = Song.awaiting_analysis.count
  end

  def show
    respond_to do |format|
      format.html
      format.json { render json: @batch.as_status_json }
    end
  end

  def create
    batch = IntakeBatch.create!(user: current_user, name: params[:name].to_s.strip.first(200).presence || "Drop")
    render json: { id: batch.id }
  end

  def upload
    file = params[:file]
    return render json: { error: "no file" }, status: :unprocessable_content unless file.respond_to?(:tempfile)
    @batch.receive!(file.tempfile, params[:relative_path].presence || file.original_filename)
    render json: { ok: true }
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  def finish
    @batch.finish_upload!
    render json: { id: @batch.id, status: @batch.status }
  end

  private

  def authorize_drop!
    authorize Song, :upload?
  end

  def visible_batches
    current_user.admin? ? IntakeBatch.all : IntakeBatch.where(user: current_user)
  end

  def set_batch
    @batch = visible_batches.find(params[:id])
  end
end
