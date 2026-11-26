# One drop into the drop box: the files, folders and archives a person handed over in one go.
# The files wait under Intake.root until the intake worker (rake intake:work) deals with them;
# IntakeItem records what became of each.
#
# status: uploading (the browser is still sending) -> queued -> processing -> done
class IntakeBatch < ApplicationRecord
  STATUSES = %w[uploading queued processing done].freeze

  belongs_to :user
  has_many :items, class_name: "IntakeItem", dependent: :delete_all

  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }

  # Hands the oldest waiting batch to the caller, or nil. Safe with more than one worker.
  def self.claim_next
    while (id = where(status: "queued").order(:created_at).pick(:id))
      claimed = where(id: id, status: "queued").update_all(status: "processing", started_at: Time.current, updated_at: Time.current)
      return find(id) if claimed == 1
    end
  end

  def incoming_dir = Intake.root.join("incoming", id)
  def work_dir = Intake.root.join("work", id)
  def originals_dir = Intake.root.join("originals", id)

  # Saves one uploaded file under the batch, at its path inside the dropped folder.
  def receive!(io, relative_path)
    raise ArgumentError, "this drop is closed" unless status == "uploading"
    target = incoming_dir.join(Intake.safe_path(relative_path))
    FileUtils.mkdir_p(target.dirname)
    File.open(target, "wb") { |out| IO.copy_stream(io, out) }
    target
  end

  def finish_upload!
    update!(status: "queued") if status == "uploading"
  end

  def counts = items.group(:status).count

  def as_status_json
    { id: id, name: name, status: status, counts: counts, error: error,
      items: items.order(:relative_path).includes(song: [ :artist, :album ]).map(&:as_status_json) }
  end
end
