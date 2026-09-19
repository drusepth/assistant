require "test_helper"

# A trip's stay as a dated place (D-place-subscriptions): the nights are
# the window, the place you follow calendars for is the source, and what
# you add from there is also Travel's.
class TripWindowsTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    users(:one).household.model_profile.update!(api_key: "")
    @trip = users(:one).trips.create!(name: "Lisbon in October", starts_on: 20.days.from_now.to_date, ends_on: 27.days.from_now.to_date)
    @stay = @trip.stays.create!(location: "Lisbon, Portugal", check_in: 20.days.from_now.to_date, check_out: 27.days.from_now.to_date)
    @place = users(:one).places.create!(name: "Lisbon, Portugal", lead_days: 7)
    @source = @place.listing_sources.create!(url: "https://lisboa.example/agenda.ics", title: "Agenda Lisboa")
    @fado = @source.happenings.create!(uid: "fado", title: "Fado night", starts_at: 22.days.from_now.change(hour: 21))
    @later = @source.happenings.create!(uid: "later", title: "After you've left", starts_at: 40.days.from_now)
  end

  test "the trip page lists what's on at the stay for those dates, and an event added from it is Travel's too" do
    get trip_path(@trip)

    assert_response :success
    assert_select "[data-trip-window='#{@stay.id}']"
    assert_match "Fado night", response.body
    assert_no_match "After you've left", response.body

    post calendar_happening_path(@fado)

    event = users(:one).events.find_by!(title: "Fado night")
    assert_equal %w[ hobbies travel ], event.sections.map(&:slug).sort
    assert_equal [ "hobbies" ], @later.add_to_calendar!.sections.map(&:slug), "outside the window is not a trip thing"
  end

  test "a stay with no place nearby is offered as one, and adding it comes back to the trip" do
    porto = @trip.stays.create!(location: "Porto", check_in: 27.days.from_now.to_date, check_out: 30.days.from_now.to_date)

    get trip_path(@trip)
    assert_select "[data-trip-unplaced='#{porto.id}']"
    assert_select "form[action=?] input[name='place[name]'][value=?]", places_path, "Porto"

    post places_path, params: { place: { name: "Porto" }, return_to: trip_path(@trip) }

    assert_redirected_to trip_path(@trip)
    assert users(:one).places.find_by(name: "Porto")
    get trip_path(@trip)
    assert_select "[data-trip-unplaced='#{porto.id}']", false
  end

  test "the watcher uses the stay's nights as the lead time and files the nudge under Travel" do
    HappeningMatch.create!(happening: @fado, target: "household", reason: "you love fado")
    watcher = Watcher::EventRadar.new(users(:one))

    watcher.scan

    suggestion = watcher.proposals.sole
    assert_match "Fado night", suggestion.title
    assert_equal %w[ hobbies travel ], suggestion.sections.map(&:slug).sort
    assert_equal %w[ hobbies travel ], suggestion.accept!.sections.map(&:slug).sort
  end

  test "a companion on the trip sees the stay against their own places, never the owner's" do
    @trip.memberships.create!(user: users(:two))
    sign_in_as users(:two)

    get trip_path(@trip)

    assert_response :success
    assert_no_match "Fado night", response.body
    assert_select "[data-trip-unplaced='#{@stay.id}']", true, "their own places have nothing near Lisbon"
  end

  test "a past trip has no while-you're-there card" do
    @trip.update!(starts_on: 30.days.ago.to_date, ends_on: 25.days.ago.to_date)
    @stay.update!(check_in: 30.days.ago.to_date, check_out: 25.days.ago.to_date)

    get trip_path(@trip)

    assert_response :success
    assert_no_match "While you", response.body
  end
end
