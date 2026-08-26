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

  test "a day two stays both claim turns the band amber and says so" do
    trip = users(:one).trips.create!(name: "Idaho", starts_on: "2026-03-01", ends_on: "2026-03-31")
    trip.stays.create!(location: "Boise", check_in: "2026-03-10", check_out: "2026-03-14")
    trip.stays.create!(location: "McCall", check_in: "2026-03-12", check_out: "2026-03-20")

    get calendar_path(year: 2026, month: 3)
    assert_response :success
    # Mar 12-14: both stays cover them (check-out day inclusive on the band).
    assert_select "a[title^='Double-booked']", count: 3, text: "2 places"
  end

  test "no travel band for trips you aren't on" do
    trip = users(:two).trips.create!(name: "Idaho", starts_on: "2026-03-01", ends_on: "2026-03-31")
    trip.stays.create!(location: "Boise", check_in: "2026-03-10", check_out: "2026-03-14")

    get calendar_path(year: 2026, month: 3)
    assert_select "a[title='Boise · Idaho']", count: 0
  end
end
