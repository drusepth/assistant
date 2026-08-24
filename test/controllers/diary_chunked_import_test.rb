require "test_helper"

# A real Day One export is thousands of entries and thousands of seals —
# more than one request should hold — and the usual way out, a background
# job, is exactly what this container may not use. So the parse is staged,
# sealed, and walked a batch per request.
class DiaryChunkedImportTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    post session_url, params: { email_address: @user.email_address, password: "password" }
    verify_recovery_kit
  end

  def day_one(count, prefix: "Entry")
    { "entries" => Array.new(count) { |i|
      { "creationDate" => (Date.new(2020, 1, 1) + i).to_time.utc.iso8601,
        "text" => "#{prefix} body number #{i}." }
    } }.to_json
  end

  def upload(content, name = "Journal.json")
    Rack::Test::UploadedFile.new(StringIO.new(content), nil, original_filename: name)
  end

  def stage(content, name = "Journal.json")
    post import_diary_entries_url, params: { file: upload(content, name) }
  end

  def step
    post import_step_diary_entries_url, as: :json
    JSON.parse(response.body)
  end

  test "staging writes nothing yet, and the progress page picks it up" do
    stage(day_one(5))
    assert_redirected_to import_diary_entries_path

    assert_equal 0, @user.diary_entries.count, "staging must not write entries"
    staged = @user.diary_imports.sole
    assert_equal 5, staged.total
    assert_equal 0, staged.cursor

    get import_diary_entries_url
    assert_response :success
    assert_match "Importing", response.body
  end

  test "the staged file is sealed, not left in the clear" do
    stage(day_one(3, prefix: "Unmistakable-staged"))

    rows = DiaryImport.connection.select_all("SELECT * FROM diary_imports").rows.flatten.map(&:to_s)
    assert_no_match(/Unmistakable-staged/, rows.join(" "),
      "a plaintext staging row would put the whole diary on disk in the clear")
  end

  test "each step writes a batch and the cursor only moves forward" do
    total = DiaryImport::BATCH + 20
    stage(day_one(total))

    first = step
    assert_equal false, first["done"]
    assert_equal DiaryImport::BATCH, first["cursor"]
    assert_equal DiaryImport::BATCH, @user.diary_entries.count

    second = step
    assert_equal true, second["done"]
    assert_equal total, @user.diary_entries.count
    assert_equal total, second["imported"]
  end

  test "the staged row is cleared when the import finishes" do
    stage(day_one(3))
    step

    assert_empty @user.diary_imports, "finished staging keeps a sealed copy of words already written"
  end

  test "stepping a finished import is harmless" do
    stage(day_one(2))
    step

    assert_nothing_raised { step }
    assert_equal true, step["done"]
    assert_equal 2, @user.diary_entries.count, "an extra step must not double-write"
  end

  test "an import survives a closed tab and resumes where it stopped" do
    total = DiaryImport::BATCH + 5
    stage(day_one(total))
    step

    # A new visit — the cursor lives in the database, not the page.
    get import_diary_entries_url
    assert_response :success
    assert_match "Importing", response.body

    step
    assert_equal total, @user.diary_entries.count
  end

  test "cancelling stops the import and keeps what already landed" do
    stage(day_one(DiaryImport::BATCH + 10))
    step
    written = @user.diary_entries.count

    delete import_diary_entries_url
    assert_redirected_to import_diary_entries_path
    assert_empty @user.diary_imports
    assert_equal written, @user.diary_entries.count
  end

  test "a new file replaces an abandoned import rather than racing it" do
    stage(day_one(10))
    stage(day_one(4, prefix: "Second"))

    assert_equal 1, @user.diary_imports.count
    assert_equal 4, @user.diary_imports.sole.total
  end

  test "an implausibly large file is refused with a sentence, not a timeout" do
    stage(day_one(DiaryImport::MAX_ENTRIES + 1))

    assert_redirected_to import_diary_entries_path
    assert_match(/more than this can import at once/i, flash[:alert])
    assert_empty @user.diary_imports
  end

  test "duplicates are counted at staging and reported at the end" do
    stage(day_one(3))
    step

    # Two of these three are already here.
    mixed = { "entries" => [
      { "creationDate" => Date.new(2020, 1, 1).to_time.utc.iso8601, "text" => "Entry body number 0." },
      { "creationDate" => Date.new(2020, 1, 2).to_time.utc.iso8601, "text" => "Entry body number 1." },
      { "creationDate" => Date.new(2021, 5, 5).to_time.utc.iso8601, "text" => "Something new." }
    ] }.to_json

    stage(mixed)
    assert_equal 1, @user.diary_imports.sole.total
    assert_equal 2, @user.diary_imports.sole.skipped

    done = step
    assert_equal 1, done["imported"]
    assert_equal 2, done["skipped"]
    assert_equal 4, @user.diary_entries.count
  end

  test "a vault change mid-import ends it honestly instead of looping" do
    stage(day_one(DiaryImport::BATCH + 5))
    step

    # The diary key is gone; the staged rows can never be opened again.
    @user.diary_setting.update!(wrapped_content_key: Vault::Crypto.random_key)

    result = step
    assert_equal true, result["done"]
    assert_match(/vault changed/i, result["error"])
    assert_empty @user.diary_imports
  end

  test "stepping needs an unlocked vault" do
    stage(day_one(3))
    post lock_diary_entries_url

    post import_step_diary_entries_url, as: :json
    assert_response :redirect
    assert_equal 0, @user.diary_entries.count
  end
end
