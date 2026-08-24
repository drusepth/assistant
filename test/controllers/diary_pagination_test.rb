require "test_helper"

# A page of entries is a page of decrypts, so the list is windowed. Before
# this, a journal past its first couple of hundred entries had no way to
# reach the older ones at all.
class DiaryPaginationTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    post session_url, params: { email_address: @user.email_address, password: "password" }
    post recovery_credentials_url
    post recovery_confirm_credentials_url
    @session = Diary::Session.new(@user.reload, @user.keyring.unlock("password"))
  end

  # Seeded through the session rather than the controller: this test is about
  # paging, and a hundred round trips would make it about nothing else.
  def seed(count, from: Date.current)
    count.times do |i|
      entry = @user.diary_entries.new(entry_date: from - i.days)
      @session.write!(entry, { "body" => "Entry number #{i}." })
    end
  end

  test "the newest page comes first and older entries stay reachable" do
    seed(DiaryEntriesController::PER_PAGE + 10)

    get diary_entries_url
    assert_response :success
    assert_match "Entry number 0.", response.body
    assert_no_match "Entry number #{DiaryEntriesController::PER_PAGE + 5}.", response.body
    assert_match "Older", response.body

    get diary_entries_url(page: 2)
    assert_response :success
    assert_match "Entry number #{DiaryEntriesController::PER_PAGE + 5}.", response.body
    assert_match "Newer", response.body
    assert_no_match "Older", response.body, "the last page must not offer another one"
  end

  test "a page beyond the end is empty rather than broken" do
    seed(3)

    get diary_entries_url(page: 99)
    assert_response :success
  end

  test "a junk page parameter falls back to the first page" do
    seed(3)

    get diary_entries_url(page: "not-a-page")
    assert_response :success
    assert_match "Entry number 0.", response.body
  end

  test "search reaches past the first page" do
    seed(DiaryEntriesController::PER_PAGE + 10)
    old = @user.diary_entries.new(entry_date: Date.current - 400)
    @session.write!(old, { "body" => "A distinctive-old-needle sits here." })

    get diary_entries_url(q: "distinctive-old-needle")
    assert_response :success
    assert_match "distinctive-old-needle", response.body
  end

  test "search stops at a cap and says so honestly" do
    limit = DiaryEntriesController::SEARCH_LIMIT
    seed(limit + 5)

    get diary_entries_url(q: "Entry number")
    assert_response :success
    assert_match(/The first #{limit} entries\s+matching/, response.body)
    assert_match "Narrow it down", response.body
  end

  test "an uncapped search reports a real count, not an at-least" do
    seed(3)

    get diary_entries_url(q: "Entry number")
    assert_response :success
    assert_match(/3 entries\s+matching/, response.body)
    assert_no_match "The first", response.body
  end

  test "the search cap stops decrypting rather than decrypting everything first" do
    seed(DiaryEntriesController::SEARCH_LIMIT + 50)

    opened = 0
    session = Diary::Session.new(@user, @user.keyring.unlock("password"))
    session.define_singleton_method(:read) do |entry|
      opened += 1
      super(entry)
    end

    session.search(@user.diary_entries.newest_first, "Entry number", limit: 10)

    assert_operator opened, :<=, Diary::Session::BATCH,
      "a capped search must stop early rather than open the whole journal first"
    assert_operator opened, :>=, 10
  end
end
