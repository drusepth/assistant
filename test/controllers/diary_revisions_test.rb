require "test_helper"

# Undo for a diary. Autosave without it is a feature that can quietly eat
# words; with it, the worst an overwrite costs is a click.
class DiaryRevisionsTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    post session_url, params: { email_address: @user.email_address, password: "password" }
    verify_recovery_kit

    post diary_entries_url, params: { entry_date: Date.current.iso8601,
      diary: { title: "First title", body: "The original afternoon." } }
    @entry = @user.diary_entries.sole
  end

  def edit(body:, title: nil)
    patch diary_entry_url(@entry), params: { entry_date: @entry.entry_date.iso8601,
      diary: { title: title, body: body } }
  end

  def session_for(user = @user) = Diary::Session.new(user, user.keyring.unlock("password"))

  test "an edit keeps the version it replaced, and it can be restored" do
    assert_difference -> { @entry.diary_revisions.count }, 1 do
      edit(body: "Rewritten, badly.", title: "First title")
    end

    get history_diary_entry_url(@entry)
    assert_response :success
    assert_match "The original afternoon.", response.body

    revision = @entry.diary_revisions.sole
    post restore_diary_entry_url(@entry, revision_id: revision.id)

    get diary_entry_url(@entry)
    assert_match "The original afternoon.", response.body
    assert_no_match "Rewritten, badly.", response.body
  end

  test "restoring keeps the version it replaced, so undo is itself undoable" do
    edit(body: "Second version.", title: "First title")
    post restore_diary_entry_url(@entry, revision_id: @entry.diary_revisions.sole.id)

    assert_equal 2, @entry.diary_revisions.count,
      "the version being replaced by a restore must be kept too"

    newest = @entry.diary_revisions.newest_first.first
    post restore_diary_entry_url(@entry, revision_id: newest.id)

    get diary_entry_url(@entry)
    assert_match "Second version.", response.body
  end

  test "autosave does not bury the version worth keeping" do
    # A writing session: many saves in quick succession.
    5.times { |i| edit(body: "Draft #{i}.", title: "First title") }

    assert_equal 1, @entry.diary_revisions.count,
      "a burst of autosaves is one sitting, so it keeps one snapshot"

    version = session_for.revisions(@entry).first.last
    assert_equal "The original afternoon.", version.body,
      "the snapshot kept must be the state before the sitting, not a draft from the middle of it"
  end

  test "a new sitting keeps a new version" do
    edit(body: "Yesterday's rewrite.", title: "First title")
    @entry.diary_revisions.update_all(created_at: 2.hours.ago)

    assert_difference -> { @entry.diary_revisions.count }, 1 do
      edit(body: "Today's rewrite.", title: "First title")
    end
  end

  test "an edit that changes nothing keeps no version" do
    @entry.diary_revisions.delete_all

    assert_no_difference -> { @entry.diary_revisions.count } do
      edit(body: "The original afternoon.", title: "First title")
    end
  end

  test "versions are sealed, and unreadable in the clear" do
    edit(body: "Unmistakable-revision-probe-9.", title: "First title")
    post restore_diary_entry_url(@entry, revision_id: @entry.diary_revisions.sole.id)

    rows = DiaryRevision.connection.select_all("SELECT * FROM diary_revisions").rows.flatten.map(&:to_s)
    assert_no_match(/Unmistakable-revision-probe-9/, rows.join(" "))
    assert_no_match(/The original afternoon/, rows.join(" "))
  end

  test "a revision ciphertext cannot be passed off as the live entry" do
    edit(body: "Rewritten.", title: "First title")
    revision = @entry.diary_revisions.sole

    # update_all, not update_column: optimistic locking scopes a record's own
    # writes to its in-memory lock_version, and this @entry is deliberately
    # stale — see DiaryEntry#rewrap_to_diary_key!.
    DiaryEntry.where(id: @entry.id).update_all(payload_ciphertext: revision.payload_ciphertext)

    assert_nil session_for.read(@entry.reload),
      "a revision blob moved into the entry must fail its tag, not silently become the entry"
  end

  test "history and restore are the author's alone" do
    edit(body: "Private drafting.", title: "First title")
    other = users(:two)
    post session_url, params: { email_address: other.email_address, password: "password" }

    get history_diary_entry_url(@entry)
    assert_response :not_found

    post restore_diary_entry_url(@entry, revision_id: @entry.diary_revisions.sole.id)
    assert_response :not_found
  end

  test "versions die with the entry" do
    edit(body: "Something.", title: "First title")
    assert_difference -> { DiaryRevision.count }, -1 do
      delete diary_entry_url(@entry)
    end
  end

  test "only the most recent versions are kept" do
    item_key = @entry.unwrap_item_key(@user, @user.keyring.unlock("password"),
      diary_key: session_for.diary_key)

    (DiaryRevision::KEEP + 5).times do |i|
      DiaryRevision.seal!(@entry, { "body" => "Version #{i}." }, item_key, force: true)
    end

    assert_equal DiaryRevision::KEEP, @entry.diary_revisions.count
  end
end
