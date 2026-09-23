require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "requires authentication" do
    get root_path
    assert_redirected_to new_session_path
  end

  test "renders for a signed-in user" do
    sign_in_as users(:one)
    users(:one).tasks.create!(title: "Overdue thing", due_on: 2.days.ago)
    users(:one).events.create!(title: "Checkup", starts_at: 2.days.from_now)

    get root_path
    assert_response :success
    assert_select "h1", text: users(:one).household.name
    assert_select "button[data-quick-add-name-param=note]", text: /Note/
    assert_match "Overdue thing", response.body
    assert_match "Checkup", response.body
  end

  test "renders inline quick-add forms for every primitive" do
    sign_in_as users(:one)

    get root_path
    assert_response :success
    assert_select "[data-controller=quick-add]" do
      assert_select "form[action=?]", tasks_path
      assert_select "form[action=?]", notes_path
      assert_select "form[action=?]", events_path
      assert_select "form[action=?]", goals_path
      # Five, not four: the four hero tiles plus the Next 7 days card's own
      # event add, which lands you back here too.
      assert_select "input[name=return_to][value=?]", root_path, count: 5
    end
  end

  test "the next-7-days card carries its own event quick-add" do
    sign_in_as users(:one)

    get root_path
    assert_response :success
    assert_select "button[data-quick-add-name-param=upcoming_event]"
    # Namespaced ids: the hero draws the same form, and two `event_title`s
    # would leave every label pointing at the wrong input.
    assert_select "#upcoming_event_event_title"
    assert_select "#event_title"
  end

  test "the hero celebrates what is true today" do
    sign_in_as users(:one)
    users(:one).household.update!(name: "The Loud House", tagline: "Chaos, catered",
      moved_in_on: Date.new(2019, 8, 8), region: "Texas, USA")
    users(:one).people.create!(name: "Mom", birthday: Date.new(1960, 8, 8), keep_in_touch: true)

    travel_to Time.utc(2026, 8, 8, 15) do
      get root_path
    end

    assert_select "h1", text: "The Loud House"
    assert_match "Chaos, catered", response.body
    assert_match "It&#39;s Mom&#39;s birthday today", response.body
    assert_match "7 years in this home today", response.body
    assert_match "Home since 2019", response.body
  end

  test "the day the dashboard shows is the household's day, not the server's" do
    sign_in_as users(:one)
    users(:one).household.update!(time_zone: "Hawaii")

    # 05:00 UTC on the 8th is still 19:00 on the 7th in Honolulu.
    travel_to Time.utc(2026, 8, 8, 5) do
      get root_path
    end

    assert_match "Friday, August 7", response.body
  end

  test "creating from a quick-add form returns to the dashboard" do
    sign_in_as users(:one)

    post tasks_path, params: { return_to: root_path, task: { title: "From the dashboard" } }
    assert_redirected_to root_path

    post events_path, params: { return_to: root_path, event: { title: "Checkup", starts_date: Date.tomorrow } }
    assert_redirected_to root_path

    post notes_path, params: { return_to: root_path, note: { body: "Remember this" } }
    assert_redirected_to root_path

    post goals_path, params: { return_to: root_path, goal: { title: "Get organized" } }
    assert_redirected_to root_path
  end

  test "ignores a non-local return_to" do
    sign_in_as users(:one)

    post tasks_path, params: { return_to: "https://evil.example", task: { title: "Sneaky" } }
    assert_redirected_to tasks_path

    post tasks_path, params: { return_to: "//evil.example", task: { title: "Sneakier" } }
    assert_redirected_to tasks_path
  end

  test "shows ongoing multi-day events in upcoming" do
    sign_in_as users(:one)
    users(:one).events.create!(title: "Conference week", starts_at: 2.days.ago, ends_at: 2.days.from_now)

    get root_path
    assert_match "Conference week", response.body
  end

  test "pending suggestions surface on the dashboard; other members' don't" do
    sign_in_as users(:one)
    users(:two).suggestions.create!(
      watcher_slug: "neglected_hobby", fingerprint: "f2", title: "Bob's nudge",
      action: { "event" => { "title" => "Practice", "starts_at" => Date.tomorrow.iso8601 } }
    )

    get root_path
    assert_no_match "From your assistant", response.body
    assert_no_match "Bob's nudge", response.body

    users(:one).suggestions.create!(
      watcher_slug: "neglected_hobby", fingerprint: "f1",
      title: "It's been a while since anything Guitar",
      action: { "event" => { "title" => "Guitar session", "starts_at" => Date.tomorrow.iso8601 } }
    )

    get root_path
    assert_match "From your assistant", response.body
    assert_match "been a while since anything Guitar", response.body
    assert_match "Add event", response.body
  end
end
