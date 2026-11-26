require "test_helper"

class IntakeControllerTest < ActionDispatch::IntegrationTest
  teardown { IntakeBatch.find_each { |b| [ b.incoming_dir, b.work_dir, b.originals_dir ].each { |d| FileUtils.rm_rf(d) } } }

  test "visitors and regular users cannot use the drop box" do
    get intake_path
    assert_redirected_to login_path
    sign_in users(:user)
    get intake_path
    assert_response :redirect
    assert_no_difference "IntakeBatch.count" do
      post intake_batches_path, params: { name: "x" }, as: :json
    end
  end

  test "a moderator drops a folder: files land under the drop with their paths and the drop is queued" do
    sign_in users(:moderator)
    get intake_path
    assert_response :success
    assert_select "#intake-drop"

    post intake_batches_path, params: { name: "My Album" }, as: :json
    batch = IntakeBatch.find(response.parsed_body["id"])
    assert_equal [ "My Album", "uploading", users(:moderator) ], [ batch.name, batch.status, batch.user ]

    post intake_batch_files_path(batch), params: { relative_path: "My Album/CD1/01.mp3", file: fixture_file_upload("tagged.mp3", "audio/mpeg") }
    assert_response :success
    post intake_batch_files_path(batch), params: { relative_path: "../../outside.mp3", file: fixture_file_upload("tagged.mp3", "audio/mpeg") }
    assert_response :success
    assert File.exist?(batch.incoming_dir.join("My Album/CD1/01.mp3"))
    assert File.exist?(batch.incoming_dir.join("outside.mp3"))

    post intake_batch_finish_path(batch), as: :json
    assert_equal "queued", batch.reload.status
    post intake_batch_files_path(batch), params: { relative_path: "late.mp3", file: fixture_file_upload("tagged.mp3", "audio/mpeg") }
    assert_response :unprocessable_content

    IntakeProcessor.new(batch, mirror: nil, log: Logger.new(IO::NULL)).run
    get intake_batch_path(batch, format: :json)
    body = response.parsed_body
    assert_equal [ "done", { "imported" => 1, "duplicate" => 1 } ], [ body["status"], body["counts"] ]
    assert_equal "Fixture Song", body["items"].find { |i| i["status"] == "imported" }.dig("song", "title")
    get intake_batch_path(batch)
    assert_response :success
    get intake_path
    assert_select "td a", text: "My Album"
  end

  test "a moderator sees only their own drops; an admin sees all" do
    theirs = IntakeBatch.create!(user: users(:admin), name: "admin drop")
    sign_in users(:moderator)
    get intake_batch_path(theirs)
    assert_response :redirect
    delete logout_path
    sign_in users(:admin)
    get intake_batch_path(theirs)
    assert_response :success
  end

  test "the old upload address leads to the drop box" do
    sign_in users(:moderator)
    get "/upload"
    assert_redirected_to "/intake"
  end
end
