require "test_helper"

# The diary's trust-critical paths (DIARY_PLAN W1): a locked diary renders
# dates and nothing else, writing works locked, reading doesn't, the
# recovery kit gates the first entry, and no other household member can
# reach any of it.
class DiaryEntriesControllerTest < ActionDispatch::IntegrationTest
  TITLE = "Unmistakable-Title-7".freeze
  BODY = "Unmistakable-body-text-42.".freeze

  def sign_in_with_password(user, password: "password")
    post session_url, params: { email_address: user.email_address, password: password }
  end

  def save_recovery_kit
    post recovery_credentials_url
    post recovery_confirm_credentials_url
  end

  def write_entry(title: TITLE, body: BODY, on: Date.current)
    post diary_entries_url, params: { entry_date: on.iso8601, diary: { title: title, body: body } }
    DiaryEntry.order(:id).last
  end

  setup do
    @user = users(:one)
    sign_in_with_password(@user)
    save_recovery_kit
  end

  test "write, list, and read back" do
    entry = write_entry
    follow_redirect!
    assert_response :success
    assert_match BODY, response.body

    get diary_entries_url
    assert_response :success
    assert_match TITLE, response.body
    assert_equal @user.id, entry.user_id
  end

  test "a locked diary shows dates and nothing else" do
    entry = write_entry
    post lock_diary_entries_url

    get diary_entries_url
    assert_response :success
    assert_no_match TITLE, response.body
    assert_no_match BODY, response.body
    assert_match "Locked", response.body
    assert_match I18n.l(entry.entry_date, format: :long), response.body, "the calendar and dates still render"

    get diary_entry_url(entry)
    assert_redirected_to diary_entries_path(return_to: diary_entry_path(entry))
  end

  test "writing works while locked; the entry reads back after unlocking" do
    post lock_diary_entries_url

    entry = write_entry(body: "Written-while-locked-99.")
    assert entry.wrapped_while_locked?

    post unlock_diary_entries_url, params: { password: "password" }
    get diary_entry_url(entry)
    assert_response :success
    assert_match "Written-while-locked-99.", response.body
  end

  test "the recovery kit gates the first entry" do
    other = users(:two)
    sign_in_with_password(other)

    get new_diary_entry_url
    assert_redirected_to diary_entries_path
    assert_equal "Save your recovery kit before you start writing.", flash[:alert]

    post diary_entries_url, params: { entry_date: Date.current.iso8601, diary: { body: "Nope." } }
    assert_equal 0, other.diary_entries.count
  end

  test "no page body ever carries another member's writing" do
    entry = write_entry

    other = users(:two)
    sign_in_with_password(other)

    get diary_entries_url
    assert_response :success
    assert_no_match TITLE, response.body
    assert_no_match BODY, response.body

    get diary_entry_url(entry)
    assert_response :not_found
  end

  test "diary responses are never stored" do
    write_entry

    get diary_entries_url
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "autosave patches the entry and answers with a bare fact" do
    entry = write_entry

    patch diary_entry_url(entry), params: { entry_date: entry.entry_date.iso8601,
      diary: { title: TITLE, body: "Autosaved-body-13." } }, as: :json
    assert_response :success
    assert JSON.parse(response.body)["saved_at"].present?
    assert_no_match "Autosaved-body-13.", response.body

    get diary_entry_url(entry)
    assert_match "Autosaved-body-13.", response.body
  end

  test "an entry can be backdated and moved" do
    entry = write_entry(on: Date.current - 3)
    assert_equal Date.current - 3, entry.entry_date

    patch diary_entry_url(entry), params: { entry_date: (Date.current - 5).iso8601,
      diary: { body: BODY } }
    assert_equal Date.current - 5, entry.reload.entry_date
  end

  test "an empty entry is refused rather than sealed" do
    assert_no_difference -> { DiaryEntry.count } do
      post diary_entries_url, params: { entry_date: Date.current.iso8601, diary: { body: "  " } }
    end
    assert_response :unprocessable_entity
  end

  test "locking the diary locks the passwords vault too" do
    write_entry
    post lock_diary_entries_url

    get credentials_url
    assert_response :success
    assert_match "Vault locked", response.body
  end

  test "deleting removes the entry" do
    entry = write_entry

    assert_difference -> { DiaryEntry.count }, -1 do
      delete diary_entry_url(entry)
    end
    assert_redirected_to diary_entries_path
  end
end
