require "test_helper"

class TodayControllerTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  setup do
    sign_in_as users(:one)
    travel_to Time.zone.local(2026, 8, 6, 12) # a Thursday, midday
  end

  test "shows overdue, due-today, and upcoming items" do
    users(:one).tasks.create!(title: "Very late", due_on: 3.days.ago)
    users(:one).tasks.create!(title: "Do today", due_on: Date.current)
    users(:one).events.create!(title: "Tonight", starts_at: Time.current.end_of_day - 1.hour)

    get today_path
    assert_response :success
    assert_match "Very late", response.body
    assert_match "Do today", response.body
    assert_match "Tonight", response.body
  end

  test "shows tomorrow's tasks and events in the get-ready section" do
    users(:one).tasks.create!(title: "Pack gym bag", due_on: Date.tomorrow)
    users(:one).events.create!(title: "Dentist checkup", starts_at: Date.tomorrow.noon)

    get today_path
    assert_response :success
    assert_match "Get ready for tomorrow", response.body
    assert_match "Pack gym bag", response.body
    assert_match "Dentist checkup", response.body
  end

  test "offers a task-for-tomorrow quick-add" do
    get today_path
    assert_match "Task for tomorrow", response.body
  end

  test "on Friday the prep section covers the weekend through Monday" do
    travel_to Time.zone.local(2026, 8, 7, 12) # a Friday
    users(:one).tasks.create!(title: "Water plants", due_on: Date.current + 1)
    users(:one).events.create!(title: "Monday standup", starts_at: Time.zone.local(2026, 8, 10, 9, 30))

    get today_path
    assert_response :success
    assert_match "Get ready for the weekend", response.body
    assert_match "Water plants", response.body
    assert_match "Monday standup", response.body
  end

  test "flags early-morning starts tomorrow" do
    users(:one).events.create!(title: "Flight to Denver", starts_at: Time.zone.local(2026, 8, 7, 6, 30))

    get today_path
    assert_match "Early start tomorrow", response.body
    assert_match "Flight to Denver at 6:30 AM", response.body
  end

  test "ongoing multi-day events appear in today's events" do
    users(:one).events.create!(title: "Grandma visiting", starts_at: 2.days.ago, ends_at: 2.days.from_now)

    get today_path
    assert_match "Grandma visiting", response.body
  end

  test "dims events that already finished today" do
    users(:one).events.create!(title: "Morning run",
      starts_at: Time.current.beginning_of_day + 6.hours, ends_at: Time.current.beginning_of_day + 7.hours)

    get today_path
    assert_match "opacity-50", response.body
  end

  test "overdue tasks offer quick reschedule buttons" do
    users(:one).tasks.create!(title: "Very late", due_on: 3.days.ago)

    get today_path
    assert_match "Move due date to today", response.body
    assert_match "Move due date to tomorrow", response.body
  end

  test "a row those buttons empty out of the list carries its own send-off" do
    users(:one).tasks.create!(title: "Very late", due_on: 3.days.ago)

    get today_path
    assert_select "#overdue .item-row[data-controller=?]", "row-dismiss"
    assert_select "#overdue button[data-row-dismiss-direction=?]", "now"
    assert_select "#overdue button[data-row-dismiss-direction=?]", "later"
  end

  test "every row on the page is named, and no name is used twice" do
    users(:one).tasks.create!(title: "Very late", due_on: 3.days.ago)
    users(:one).tasks.create!(title: "Do today", due_on: Date.current)
    users(:one).tasks.create!(title: "Pack gym bag", due_on: Date.tomorrow)
    users(:one).tasks.create!(title: "Someday thing")
    # Event.overlapping is inclusive at both ends, so this one is genuinely
    # on today's list *and* tomorrow's — the case a bare dom_id gets wrong.
    users(:one).events.create!(title: "Conference", starts_at: Time.current.beginning_of_day + 9.hours,
      ends_at: Date.tomorrow.end_of_day)

    get today_path
    rows = css_select(".item-row")
    assert rows.any?
    assert_empty rows.reject { |row| row["id"].present? }, "an item row with no id"

    ids = css_select("[id]").map { |el| el["id"] }
    assert_empty ids.tally.select { |_id, count| count > 1 }.keys, "ids used more than once"
  end

  test "a row with no reschedule buttons has nothing to animate out" do
    users(:one).tasks.create!(title: "Do today", due_on: Date.current)

    get today_path
    assert_select "#due-today .item-row[data-controller=row-dismiss]", false
  end

  test "undated tasks offer them too — claiming is the only way they land on a day" do
    users(:one).tasks.create!(title: "Someday thing")

    get today_path
    assert_select "#unscheduled form[action=?]", reschedule_task_path(Task.find_by(title: "Someday thing"), to: "today")
  end

  test "a late task says how late rather than making you subtract" do
    users(:one).tasks.create!(title: "Very late", due_on: 3.days.ago)

    get today_path
    assert_match "3 days late", response.body
  end

  test "the glance strip sizes the day and jumps to each card" do
    users(:one).tasks.create!(title: "Very late", due_on: 3.days.ago)
    users(:one).tasks.create!(title: "Do today", due_on: Date.current)
    users(:one).events.create!(title: "Tonight", starts_at: Time.current.end_of_day - 1.hour)

    get today_path
    assert_select "a[href='#overdue']", text: "1 overdue"
    assert_select "a[href='#due-today']", text: "1 due today"
    assert_select "a[href='#todays-events']", text: "1 event"
    assert_select "#overdue"
    assert_select "#due-today"
    assert_select "#todays-events"
  end

  test "the glance strip stays away on a clear day" do
    get today_path
    assert_select "a[href='#overdue']", false
    assert_select "a[href='#due-today']", false
  end

  test "groups coming-up events by day" do
    users(:one).events.create!(title: "Team offsite", starts_at: Time.zone.local(2026, 8, 9, 10))

    get today_path
    assert_match "Sunday, Aug 9", response.body
    assert_match "Team offsite", response.body
  end

  test "caps the unscheduled list and links to the rest" do
    7.times { |i| users(:one).tasks.create!(title: "Someday #{i}") }

    get today_path
    assert_match "View all 7 unscheduled tasks", response.body
  end

  test "unscheduled tasks list oldest first, so old ones can't hide" do
    fresh = users(:one).tasks.create!(title: "Fresh idea")
    forgotten = users(:one).tasks.create!(title: "Forgotten chore")
    forgotten.update_columns(created_at: 6.months.ago)

    get today_path
    assert_operator response.body.index("Forgotten chore"), :<, response.body.index("Fresh idea")
  end

  test "does not show other users' private items" do
    users(:two).tasks.create!(title: "Bob's secret errand", due_on: Date.current)

    get today_path
    assert_response :success
    assert_no_match "Bob&#39;s secret errand", response.body
  end
end
