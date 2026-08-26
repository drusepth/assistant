require "test_helper"

# W2 — the things that make a diary a habit rather than a form: search over
# what is otherwise unsearchable, the same day in past years, and a prompt
# that never involves a model.
class DiaryHabitTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    post session_url, params: { email_address: @user.email_address, password: "password" }
    verify_recovery_kit
  end

  def write(body:, title: nil, on: Date.current)
    post diary_entries_url, params: { entry_date: on.iso8601, diary: { title: title, body: body } }
    DiaryEntry.order(:id).last
  end

  test "search reaches the whole journal, not just the listed page" do
    write(body: "The kitchen tap finally stopped dripping.", on: Date.current - 400)
    write(body: "Nothing much happened.", on: Date.current)

    get diary_entries_url(q: "dripping")
    assert_response :success
    assert_match "kitchen tap", response.body
    assert_no_match "Nothing much happened", response.body
  end

  test "search matches titles and the writer's mood word" do
    entry = write(body: "A long walk.", title: "Distinctive-Heading")
    patch diary_entry_url(entry), params: { entry_date: entry.entry_date.iso8601,
      diary: { body: "A long walk.", mood: "restless" } }

    get diary_entries_url(q: "distinctive-heading")
    assert_match "Distinctive-Heading", response.body

    get diary_entries_url(q: "restless")
    assert_match "Distinctive-Heading", response.body
  end

  test "search is not offered while locked, and reveals nothing if asked for" do
    write(body: "Sealed-search-target-31.")
    post lock_diary_entries_url

    get diary_entries_url(q: "Sealed-search-target-31")
    assert_response :success
    assert_no_match "Sealed-search-target-31", response.body
  end

  test "on this day surfaces past years and never today" do
    write(body: "A-year-ago-today-text.", on: Date.current - 1.year)
    write(body: "Written-just-now-text.", on: Date.current)

    get diary_entries_url
    assert_response :success

    on_this_day = response.body.split("On this day").last.split("</section>").first
    assert_match "A-year-ago-today-text", on_this_day
    assert_no_match "Written-just-now-text", on_this_day
  end

  test "the writing prompt is a first-party string chosen by date" do
    assert_equal Diary::Prompts.for(Date.current), Diary::Prompts.for(Date.current)
    assert_includes Diary::Prompts::ALL, Diary::Prompts.for(Date.current)

    get new_diary_entry_url
    assert_response :success
    assert_match CGI.escapeHTML(Diary::Prompts.for(Date.current)), response.body
  end

  test "prompts can be turned off, and stay off" do
    write(body: "Something.")

    patch settings_diary_entries_url, params: { prompts_enabled: "0" }
    assert_equal false, @user.reload.diary_setting.prompts_enabled

    get new_diary_entry_url
    assert_no_match CGI.escapeHTML(Diary::Prompts.for(Date.current)), response.body
  end

  # The assertion above only catches a leak on the day the rotation happens to
  # pick the leaking string, which is how the placeholder fallback sat in the
  # page as one of the fourteen prompts and failed one day in fourteen. Off
  # means off on every date, so check every date's prompt rather than today's.
  test "prompts turned off leaks no prompt on any day of the rotation" do
    write(body: "Something.")
    patch settings_diary_entries_url, params: { prompts_enabled: "0" }

    get new_diary_entry_url

    Diary::Prompts::ALL.each do |prompt|
      assert_no_match CGI.escapeHTML(prompt), response.body,
        "#{prompt.inspect} reaches a writer who turned prompts off"
    end
  end

  test "toggling a dial never mistakes a fresh settings row for a broken one" do
    write(body: "Something.")
    patch settings_diary_entries_url, params: { prompts_enabled: "0" }

    setting = @user.reload.diary_setting
    assert_not setting.lost_entries?, "turning off prompts must not look like a password reset"
    assert setting.wrapped_content_key.present?
  end

  test "the month calendar navigates without leaking anything" do
    write(body: "Distinct-past-body.", on: Date.current - 2.months)

    get diary_entries_url(month: (Date.current - 2.months).strftime("%Y-%m"))
    assert_response :success
    assert_match I18n.l(Date.current - 2.months, format: "%B %Y"), response.body
  end

  test "the streak counts back from today and tolerates writing in the evening" do
    assert_equal 0, Diary::Streak.new([]).length
    assert_equal 3, Diary::Streak.new([ Date.current, Date.yesterday, Date.current - 2 ]).length
    assert_equal 2, Diary::Streak.new([ Date.yesterday, Date.current - 2 ]).length,
      "not having written yet today shouldn't read as a broken streak"
    assert_equal 0, Diary::Streak.new([ Date.current - 3 ]).length
    assert_equal 1, Diary::Streak.new([ Date.current, Date.current - 2 ]).length
  end
end
