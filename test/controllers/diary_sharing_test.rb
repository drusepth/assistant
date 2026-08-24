require "test_helper"

# W4 — the one exception to private-absolutely, and the emergency dial.
# Sharing is per-entry, read-only, and revocable; the diary stays out of
# emergency access unless its author says otherwise.
class DiarySharingTest < ActionDispatch::IntegrationTest
  BODY = "Unmistakable-shared-body-64.".freeze

  setup do
    @author = users(:one)
    @reader = users(:two)
    sign_in(@reader) # give the reader a keyring so they can be shared with
    sign_in(@author)
  end

  def sign_in(user)
    post session_url, params: { email_address: user.email_address, password: "password" }
    post recovery_credentials_url
    post recovery_confirm_credentials_url
  end

  def write(body: BODY, title: "Shared entry")
    post diary_entries_url, params: { entry_date: Date.current.iso8601, diary: { title: title, body: body } }
    DiaryEntry.order(:id).last
  end

  def share(entry, with:)
    post share_diary_entry_url(entry, grantee_id: with.id)
  end

  test "a shared entry is readable by the reader and by nobody else" do
    entry = write
    share(entry, with: @reader)

    assert entry.reload.visible_to?(@reader)
    assert_equal 1, entry.diary_entry_keys.count
    assert_empty entry.diary_entry_keys.where(user: @author), "the author never holds a key row"

    sign_in(@reader)
    get diary_entry_url(entry)
    assert_response :success
    assert_match BODY, response.body
  end

  test "the reader sees it in its own strip, not mixed into their journal" do
    entry = write
    share(entry, with: @reader)

    sign_in(@reader)
    get diary_entries_url
    assert_response :success
    assert_match "Shared with you", response.body
    assert_match @author.name, response.body
  end

  test "sharing is read-only — a reader cannot edit or delete" do
    entry = write
    share(entry, with: @reader)

    sign_in(@reader)
    get edit_diary_entry_url(entry)
    assert_response :not_found

    patch diary_entry_url(entry), params: { diary: { body: "Rewritten by someone else." } }
    assert_response :not_found

    delete diary_entry_url(entry)
    assert_response :not_found
    assert DiaryEntry.exists?(entry.id)
  end

  test "revoking re-keys the entry so an old wrap opens nothing" do
    entry = write
    share(entry, with: @reader)
    old_wrap = entry.reload.diary_entry_keys.sole.wrapped_item_key

    delete unshare_diary_entry_url(entry, grantee_id: @reader.id)

    assert_empty entry.reload.diary_entry_keys
    assert_not entry.visible_to?(@reader)

    # Even replaying the destroyed wrap gains nothing: the item key rotated.
    DiaryEntryKey.create!(diary_entry: entry, user: @reader, wrapped_item_key: old_wrap)
    reader_key = @reader.keyring.unlock("password")
    assert_nil Diary::Session.new(@reader, reader_key).read(entry.reload)

    # And the author still reads their own entry, unchanged.
    assert_equal BODY, Diary::Session.new(@author, @author.keyring.unlock("password")).read(entry)["body"]
  end

  test "sharing and revoking land in the diary's own history, not the passwords vault's" do
    entry = write
    share(entry, with: @reader)

    follow_redirect! # consume the share flash so it can't bleed onto the next page

    assert_equal %w[ shared ], entry.reload.vault_events.pluck(:action)
    assert_equal "DiaryEntry", entry.vault_events.sole.subject_type
    assert_empty @author.vault_events.for_container("Credential").where(subject_type: "DiaryEntry"),
      "a diary event must never be scoped into the passwords vault's history"

    get credentials_url
    assert_response :success
    assert_no_match "Shared with #{@reader.name}", response.body,
      "a diary share must not surface in the passwords vault's activity"

    get diary_entry_url(entry)
    assert_match "Shared with #{@reader.name}", response.body
  end

  test "a section-wide grant still cannot reach a diary entry" do
    entry = write
    section = Section.find_by(slug: "people") || Section.create!(name: "People", slug: "people", position: 97)
    AccessGrant.create!(grantor: @author, grantee: @reader, subject: section)

    assert_not entry.reload.visible_to?(@reader)
  end

  test "emergency access excludes the diary by default" do
    write
    role = EmergencyContact.escrow!(owner: @author, contact: @reader,
      vault_key: @author.keyring.unlock("password"), wait_days: 1)
    role.update!(requested_at: 2.days.ago)

    sign_in(@reader)
    get access_emergency_contact_url(role)
    assert_response :success
    assert_no_match BODY, response.body
    assert_no_match "#{@author.name}'s diary", response.body
  end

  test "emergency access includes the diary once its author turns it on" do
    write
    patch settings_diary_entries_url, params: { emergency_included: "1" }
    assert @author.reload.diary_setting.emergency_included?

    role = EmergencyContact.escrow!(owner: @author, contact: @reader,
      vault_key: @author.keyring.unlock("password"), wait_days: 1)
    role.update!(requested_at: 2.days.ago)

    sign_in(@reader)
    get access_emergency_contact_url(role)
    assert_response :success
    assert_match "#{@author.name}'s diary", response.body
    assert_match BODY, response.body
  end

  test "an emergency read does not rewrite the author's entries" do
    post lock_diary_entries_url
    entry = write # written locked, so it carries the RSA wrap
    assert entry.wrapped_while_locked?

    post unlock_diary_entries_url, params: { password: "password" }
    patch settings_diary_entries_url, params: { emergency_included: "1" }

    role = EmergencyContact.escrow!(owner: @author, contact: @reader,
      vault_key: @author.keyring.unlock("password"), wait_days: 1)
    role.update!(requested_at: 2.days.ago)

    sign_in(@reader)
    get access_emergency_contact_url(role)
    assert_response :success
    assert entry.reload.wrapped_while_locked?,
      "reading someone else's diary must not rewrite their wraps"
  end
end
