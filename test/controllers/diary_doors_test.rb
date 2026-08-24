require "test_helper"

# W3 — arriving and leaving. Both run in-request, because both handle the
# writing in the clear and neither may hand it to the job queue.
class DiaryDoorsTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    post session_url, params: { email_address: @user.email_address, password: "password" }
    verify_recovery_kit
    @session = Diary::Session.new(@user, nil)
  end

  def upload(content, name)
    Rack::Test::UploadedFile.new(StringIO.new(content), nil, original_filename: name)
  end

  def zip_of(files)
    buffer = Zip::OutputStream.write_buffer do |archive|
      files.each do |name, body|
        archive.put_next_entry(name)
        archive.write(body)
      end
    end
    buffer.rewind
    buffer.read
  end

  # Importing is staged and then walked a batch at a time, so a test that
  # wants entries has to drive it the way the page does.
  def import_file(content, name)
    post import_diary_entries_url, params: { file: upload(content, name) }
    drive_import
  end

  def drive_import(limit: 50)
    limit.times do
      post import_step_diary_entries_url, as: :json
      return JSON.parse(response.body) if JSON.parse(response.body)["done"]
    end
    flunk "import did not finish"
  end

  def bodies
    diary = Diary::Session.new(@user.reload, nil)
    @user.diary_entries.order(:entry_date).map { |entry| [ entry.entry_date, entry ] }
  end

  test "a Day One export imports with dates and titles" do
    payload = { "entries" => [
      { "creationDate" => "2021-03-04T09:30:00Z", "text" => "# The move\n\nBoxes everywhere." },
      { "creationDate" => "2021-03-06T21:00:00Z", "text" => "Quiet day. Unpacked the kitchen." }
    ] }.to_json

    import_file(payload, "Journal.json")
    assert_equal 2, @user.diary_entries.count

    get diary_entries_url
    assert_match "The move", response.body
    assert_match "Unpacked the kitchen", response.body
    assert_equal [ Date.new(2021, 3, 4), Date.new(2021, 3, 6) ],
      @user.diary_entries.order(:entry_date).pluck(:entry_date).map(&:to_date)
  end

  test "a zip of Markdown imports, taking dates from front matter or the filename" do
    archive = zip_of(
      "journal/2022-07-01-first.md" => "Filename dated this one.",
      "journal/whatever.md" => "---\ndate: 2022-07-02\ntitle: From front matter\n---\n\nBody here.",
      "journal/undated.md" => "No date anywhere, so this must be skipped.",
      "__MACOSX/._2022-07-01-first.md" => "junk"
    )

    import_file(archive, "journal.zip")
    assert_equal 2, @user.diary_entries.count

    get diary_entries_url
    assert_match "From front matter", response.body
    assert_no_match "No date anywhere", response.body
  end

  test "re-importing the same file adds nothing" do
    payload = { "entries" => [ { "creationDate" => "2021-03-04T09:30:00Z", "text" => "Once." } ] }.to_json

    import_file(payload, "Journal.json")
    assert_equal 1, @user.diary_entries.count

    # Nothing to stage at all, so it never gets as far as a progress bar.
    post import_diary_entries_url, params: { file: upload(payload, "Journal.json") }
    assert_redirected_to import_diary_entries_path
    assert_match(/already in your diary/i, flash[:alert])
    assert_equal 1, @user.diary_entries.count, "the same entry must not land twice"
  end

  test "imported entries are sealed, not stored in the clear" do
    payload = { "entries" => [ { "creationDate" => "2021-03-04T09:30:00Z",
                                 "text" => "Unmistakable-imported-text-88." } ] }.to_json
    import_file(payload, "Journal.json")

    row = DiaryEntry.connection.select_one("SELECT * FROM diary_entries")
    assert_no_match(/Unmistakable-imported-text-88/, row.values.map(&:to_s).join(" "))
  end

  test "importing needs an unlocked vault" do
    post lock_diary_entries_url

    post import_diary_entries_url, params: { file: upload("{}", "Journal.json") }
    assert_redirected_to diary_entries_path(return_to: import_diary_entries_path)
  end

  test "export round-trips back through import" do
    post diary_entries_url, params: { entry_date: "2023-01-09",
      diary: { title: "A title: with a colon", body: "The body of it.", mood: "settled" } }

    post export_diary_entries_url, params: { password: "password" }
    assert_response :success
    assert_equal "application/zip", response.media_type

    names = []
    Zip::File.open_buffer(StringIO.new(response.body)) { |zip| names = zip.map(&:name) }
    assert_includes names, "manifest.json"
    assert_includes names, "entries/2023-01-09.md"

    # The real test of an export: it comes back in.
    @user.diary_entries.destroy_all
    import_file(response.body, "diary.zip")

    restored = @user.diary_entries.reload.sole
    assert_equal Date.new(2023, 1, 9), restored.entry_date

    get diary_entry_url(restored)
    assert_match "A title: with a colon", response.body
    assert_match "The body of it.", response.body
  end

  test "export refuses without a password confirmation" do
    post diary_entries_url, params: { entry_date: Date.current.iso8601, diary: { body: "Private." } }

    post export_diary_entries_url, params: { password: "not-my-password" }
    assert_redirected_to diary_entries_path
    assert_equal "Confirm the export with your password.", flash[:alert]
  end

  test "the household archive carries no diary at all" do
    post diary_entries_url, params: { entry_date: Date.current.iso8601,
      diary: { body: "Unmistakable-archive-probe-5." } }

    zip = Users::Export.new(@user.reload).call
    manifest = nil
    contents = []
    Zip::File.open_buffer(zip) do |archive|
      manifest = JSON.parse(archive.find_entry("manifest.json").get_input_stream.read)
      contents = archive.map(&:name)
    end

    assert_empty contents.grep(/diary/i), "the archive must not carry a diary file"
    assert_match(/not included at all/, manifest["diary"])
    Zip::File.open_buffer(zip) do |archive|
      archive.each do |file|
        next if file.directory?

        assert_no_match(/Unmistakable-archive-probe-5/, file.get_input_stream.read.to_s)
      end
    end
  end
end
