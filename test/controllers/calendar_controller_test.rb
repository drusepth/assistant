require "test_helper"

class CalendarControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "renders the current month with visible events" do
    users(:one).events.create!(title: "Dentist", starts_at: Date.current.noon)
    users(:two).events.create!(title: "Bob private", starts_at: Date.current.noon)

    get calendar_path
    assert_response :success
    assert_match "Dentist", response.body
    assert_no_match "Bob private", response.body
  end

  test "shows multi-day events on every day they span" do
    users(:one).events.create!(title: "Beach trip",
      starts_at: Date.new(2026, 3, 10).noon, ends_at: Date.new(2026, 3, 13).noon)

    get calendar_path(year: 2026, month: 3)
    assert_response :success
    # One cell entry per spanned day, Mar 10-13: a text link on desktop and a dot on mobile.
    assert_select "a[title='Beach trip'] span.truncate", count: 4, text: "Beach trip"
    assert_select "a[aria-label='Beach trip']", count: 4
  end

  test "renders a specific month" do
    get calendar_path(year: 2026, month: 1)
    assert_response :success
    assert_select "h1", text: "January 2026"
  end

  test "the travel band shows where you'll be, on your trips and on trips you joined" do
    trip = users(:two).trips.create!(name: "Idaho", starts_on: "2026-03-01", ends_on: "2026-03-31")
    trip.memberships.create!(user: users(:one))
    trip.stays.create!(location: "Boise", check_in: "2026-03-10", check_out: "2026-03-17")

    get calendar_path(year: 2026, month: 3)
    assert_response :success
    # The place name prints on the check-in day and on Mondays; the rest of
    # the run is a tinted band linking to the trip (check-out day inclusive).
    assert_select "a[title='Boise · Idaho']", count: 8
    assert_select "a[title='Boise · Idaho']", text: "Boise", count: 2 # check-in Tue Mar 10 + Mon Mar 16
  end

  test "a night two stays both claim turns the band amber and says so" do
    trip = users(:one).trips.create!(name: "Idaho", starts_on: "2026-03-01", ends_on: "2026-03-31")
    trip.stays.create!(location: "Boise", check_in: "2026-03-10", check_out: "2026-03-14")
    trip.stays.create!(location: "McCall", check_in: "2026-03-12", check_out: "2026-03-20")

    get calendar_path(year: 2026, month: 3)
    assert_response :success
    # Mar 12 and 13 are nights both stays claim. Mar 14 is not — Boise's
    # band shows that morning, but the night is McCall's alone.
    assert_select "a[title^='Double-booked']", count: 2, text: "2 places"
  end

  test "a seamless move day is not a double booking, and prints where you'll sleep" do
    trip = users(:one).trips.create!(name: "Idaho", starts_on: "2026-03-01", ends_on: "2026-03-31")
    trip.stays.create!(location: "Boise", check_in: "2026-03-10", check_out: "2026-03-14")
    trip.stays.create!(location: "McCall", check_in: "2026-03-14", check_out: "2026-03-20")

    get calendar_path(year: 2026, month: 3)
    assert_select "a[title^='Double-booked']", count: 0
    # The handoff day belongs to the stay whose night it is.
    assert_select "a[title='McCall · Idaho']", text: "McCall", minimum: 1
  end

  test "no travel band for trips you aren't on" do
    trip = users(:two).trips.create!(name: "Idaho", starts_on: "2026-03-01", ends_on: "2026-03-31")
    trip.stays.create!(location: "Boise", check_in: "2026-03-10", check_out: "2026-03-14")

    get calendar_path(year: 2026, month: 3)
    assert_select "a[title='Boise · Idaho']", count: 0
  end

  test "tasks show on their due date, done ones struck through, private ones hidden" do
    users(:one).tasks.create!(title: "Renew passport", due_on: "2026-03-12")
    users(:one).tasks.create!(title: "File taxes", due_on: "2026-03-05", completed_at: Time.current)
    users(:two).tasks.create!(title: "Bob private task", due_on: "2026-03-12")

    get calendar_path(year: 2026, month: 3)
    assert_select "a[title='Renew passport']", text: "Renew passport"
    assert_select "a[title='File taxes — done'] span.line-through", text: "File taxes"
    assert_select "a[aria-label='Task: Renew passport']"
    assert_no_match "Bob private task", response.body
  end

  test "reminders show on their day, standing ones on every occurrence ahead, only your own" do
    travel_to Time.zone.local(2026, 3, 2, 8) do
      users(:one).reminders.create!(body: "Call the pharmacy", deliver_on: "2026-03-04", deliver_time: "16:00")
      users(:one).reminders.create!(body: "Water plants", deliver_on: "2026-03-05", deliver_time: "09:00", repeat: "weekly")
      users(:two).reminders.create!(body: "Bob private ping", deliver_on: "2026-03-04", deliver_time: "10:00")

      get calendar_path(year: 2026, month: 3)
    end
    assert_select "a[title='Reminder: Call the pharmacy — 4:00 PM']", count: 1
    # Thursdays Mar 5 through Apr 2 — the grid's last row runs into April.
    assert_select "a[title='Reminder: Water plants — 9:00 AM']", count: 5
    assert_no_match "Bob private ping", response.body
  end

  test "layers toggle what shows and are remembered" do
    users(:one).events.create!(title: "Dentist", starts_at: Date.new(2026, 3, 10).noon)
    users(:one).tasks.create!(title: "Renew passport", due_on: "2026-03-12")

    get calendar_path(year: 2026, month: 3, layers: "tasks")
    assert_no_match "Dentist", response.body
    assert_match "Renew passport", response.body
    assert_select "a.tab-active[aria-pressed='true']", text: /Tasks/
    assert_select "a[aria-pressed='false'][href*='layers=events%2Ctasks']", text: /Events/

    get calendar_path(year: 2026, month: 3)
    assert_no_match "Dentist", response.body

    get calendar_path(year: 2026, month: 3, layers: "")
    assert_no_match "Renew passport", response.body
  end
end
