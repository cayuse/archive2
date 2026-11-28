require "test_helper"

class IntakeWatcherTest < ActiveSupport::TestCase
  setup do
    @root = Pathname.new(Dir.mktmpdir("watched"))
    @user = users(:admin)
    @later = Time.current + IntakeWatcher::SETTLE + 1.minute
  end

  teardown do
    FileUtils.rm_rf(@root)
    IntakeBatch.find_each { |b| FileUtils.rm_rf(b.incoming_dir) }
  end

  def put(rel, body = "audio #{rel}")
    path = @root.join(rel)
    FileUtils.mkdir_p(path.dirname)
    File.write(path, body)
  end

  def scan(name = "lidarr", now: @later) = IntakeWatcher.new(name, @root, user: @user, now: now, log: Logger.new(IO::NULL)).scan

  def taken(batch) = Dir.glob("**/*", base: batch.incoming_dir).select { |f| File.file?(batch.incoming_dir.join(f)) }.sort

  test "each album folder becomes one batch; junk, hidden files and partial downloads are left alone" do
    put("Kane Brown/Experiment (2018)/01 Baby Come Back.flac")
    put("Kane Brown/Experiment (2018)/02 Good as You.flac")
    put("Kane Brown/Experiment (2018)/cover.jpg")
    put("Kane Brown/Experiment (2018)/._01 Baby Come Back.flac")
    put("Kane Brown/Experiment (2018)/03 Lose It.flac.part")
    put("Пётр Ильич Чайковский/Лебединое озеро/01 Сцена.mp3")
    put(".Trash/old.mp3")
    batches = scan.sort_by(&:name)
    assert_equal [ "lidarr: Kane Brown/Experiment (2018)", "lidarr: Пётр Ильич Чайковский/Лебединое озеро" ], batches.map(&:name)
    assert batches.all? { |b| b.status == "queued" && b.source == "watch:lidarr" && b.user == @user }
    assert_equal [ "Kane Brown/Experiment (2018)/01 Baby Come Back.flac", "Kane Brown/Experiment (2018)/02 Good as You.flac" ], taken(batches.first)
    assert_equal [ "Пётр Ильич Чайковский/Лебединое озеро/01 Сцена.mp3" ], taken(batches.last)
    assert File.exist?(@root.join("Kane Brown/Experiment (2018)/01 Baby Come Back.flac")), "the watched folder is never changed"
  end

  test "a folder still being written to waits until it has settled" do
    put("Band/Album/01.mp3")
    assert_empty scan(now: Time.current)
    assert_equal 1, scan.size
  end

  test "a file is taken once, and again only when it changes (an upgrade replacing it)" do
    put("Band/Album/01.mp3")
    put("Band/Album/02.mp3")
    assert_equal 1, scan.size
    assert_empty scan, "nothing new"
    put("Band/Album/02.mp3", "a better file, longer")
    again = scan
    assert_equal [ [ "Band/Album/02.mp3" ] ], again.map { |b| taken(b) }
  end

  test "the drop folder takes any layout: loose files together, each top folder on its own" do
    put("loose 1.mp3")
    put("loose 2.flac")
    put("Some Purchase [FLAC]/CD1/01.flac")
    put("Some Purchase [FLAC]/CD2/01.flac")
    put("amazon-order.zip", "PK")
    names = scan("drop").map(&:name).sort
    assert_equal [ "drop: Some Purchase [FLAC]", "drop: loose files" ], names
    loose = IntakeBatch.find_by!(name: "drop: loose files")
    assert_equal [ "amazon-order.zip", "loose 1.mp3", "loose 2.flac" ], taken(loose)
  end

  test "watching waits until the library's measurements are loaded" do
    put("Band/Album/01.mp3")
    with_env("INTAKE_WATCH" => "lidarr=#{@root}", "INTAKE_WATCH_USER" => nil) do
      assert_empty IntakeWatcher.scan_all(now: @later), "no measurements yet: every copy would look new"
      SongMeasurement.create!(song: songs(:one), measure_version: 2, score_version: 1, verdict: "ok", measured_at: Time.current)
      assert_equal 1, IntakeWatcher.scan_all(now: @later).size
    end
  end

  test "the folders come from INTAKE_WATCH; batches are filed under INTAKE_WATCH_USER or the first admin" do
    with_env("INTAKE_WATCH" => "lidarr=/watch/lidarr; drop = /watch/drop ;bad", "INTAKE_WATCH_USER" => nil) do
      assert_equal [ [ "lidarr", Pathname("/watch/lidarr") ], [ "drop", Pathname("/watch/drop") ] ], IntakeWatcher.watches
      assert_equal User.admins.order(:created_at).first, IntakeWatcher.user
    end
    with_env("INTAKE_WATCH_USER" => users(:moderator).email) { assert_equal users(:moderator), IntakeWatcher.user }
  end

  def with_env(vars)
    old = vars.keys.to_h { |k| [ k, ENV[k] ] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    old.each { |k, v| ENV[k] = v }
  end
end
