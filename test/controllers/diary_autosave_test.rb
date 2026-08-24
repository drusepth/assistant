require "test_helper"

# Autosave has to cover the *first* sitting — the longest anyone writes
# without saving — and it must never let one tab quietly overwrite another.
class DiaryAutosaveTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    post session_url, params: { email_address: @user.email_address, password: "password" }
    verify_recovery_kit
  end

  def autosave_create(body:, title: nil)
    post diary_entries_url, params: { entry_date: Date.current.iso8601,
      diary: { title: title, body: body } }, as: :json
  end

  test "the first autosave of a new entry creates it and hands back where to save next" do
    assert_difference -> { DiaryEntry.count }, 1 do
      autosave_create(body: "Half a thought, still typing.")
    end
    assert_response :success

    body = JSON.parse(response.body)
    entry = @user.diary_entries.sole
    assert_equal diary_entry_path(entry), body["url"]
    assert_equal entry.lock_version, body["lock_version"]
    assert body["saved_at"].present?
    assert_no_match "Half a thought", response.body, "the response is a fact, not the entry"
  end

  test "autosaving the same draft twice edits it rather than making a second copy" do
    autosave_create(body: "First pass.")
    entry = @user.diary_entries.sole
    url = JSON.parse(response.body)["url"]

    assert_no_difference -> { DiaryEntry.count } do
      patch url, params: { entry_date: entry.entry_date.iso8601,
        diary: { body: "First pass, extended." } }, as: :json
    end
    assert_response :success

    get diary_entry_url(entry)
    assert_match "First pass, extended.", response.body
  end

  test "an empty draft is not created" do
    assert_no_difference -> { DiaryEntry.count } do
      autosave_create(body: "   ")
    end
    assert_response :unprocessable_entity
  end

  test "a second tab is refused rather than silently overwritten" do
    autosave_create(body: "Original.")
    entry = @user.diary_entries.sole
    stale_version = entry.lock_version

    # Tab A saves.
    patch diary_entry_url(entry), params: { entry_date: entry.entry_date.iso8601,
      diary: { body: "Tab A wrote this." }, diary_entry: { lock_version: stale_version } }, as: :json
    assert_response :success

    # Tab B still holds the version it rendered with.
    patch diary_entry_url(entry), params: { entry_date: entry.entry_date.iso8601,
      diary: { body: "Tab B wrote this." }, diary_entry: { lock_version: stale_version } }, as: :json
    assert_response :conflict
    assert_match(/saved somewhere else/i, JSON.parse(response.body)["message"])

    get diary_entry_url(entry)
    assert_match "Tab A wrote this.", response.body
    assert_no_match "Tab B wrote this.", response.body
  end

  test "the lock version handed back keeps a single tab saving indefinitely" do
    autosave_create(body: "One.")
    entry = @user.diary_entries.sole
    version = JSON.parse(response.body)["lock_version"]

    3.times do |i|
      patch diary_entry_url(entry), params: { entry_date: entry.entry_date.iso8601,
        diary: { body: "Pass #{i}." }, diary_entry: { lock_version: version } }, as: :json
      assert_response :success, "a tab following the handed-back version must never conflict with itself"
      version = JSON.parse(response.body)["lock_version"]
    end

    get diary_entry_url(entry)
    assert_match "Pass 2.", response.body
  end

  test "the HTML form path still works without a lock version" do
    post diary_entries_url, params: { entry_date: Date.current.iso8601, diary: { body: "Plain form save." } }
    entry = @user.diary_entries.sole
    assert_redirected_to diary_entry_path(entry)

    patch diary_entry_url(entry), params: { entry_date: entry.entry_date.iso8601,
      diary: { body: "Edited by form." } }
    assert_redirected_to diary_entry_path(entry)
  end
end
