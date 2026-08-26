require "test_helper"

# The planning half of trips (D-trip-spine): trips typed ahead of going,
# their itineraries, and who can touch what (D-trip-companions).
class TripPlanningTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  setup do
    travel_to Time.zone.local(2026, 6, 15, 12)
    sign_in_as users(:one)
  end

  teardown { travel_back }

  test "a trip can be planned ahead, with no photos and no box" do
    assert_difference("Trip.count", 1) do
      post trips_path, params: { trip: { name: "Santa Fe", place_label: "Santa Fe, New Mexico",
        starts_on: "2026-09-01", ends_on: "2026-10-31", description: "Two months in the high desert" } }
    end
    trip = Trip.sole
    assert_redirected_to trip
    assert_not trip.placed?

    get trip_path(trip)
    assert_response :success
    assert_match "Itinerary", response.body
    assert_match "Two months in the high desert", response.body
  end

  test "the manual form can't smuggle in a box" do
    post trips_path, params: { trip: { name: "Sly", starts_on: "2026-09-01", ends_on: "2026-09-30",
      south: "10", west: "10", north: "20", east: "20" } }
    assert_not Trip.sole.placed?
  end

  test "stays and legs build the itinerary, and the gap callout names the uncovered nights" do
    trip = create_trip
    post trip_stays_path(trip), params: { stay: { location: "Boise", kind: "airbnb",
      booking_status: "booked", check_in: "2026-09-01", check_out: "2026-09-10" } }
    assert_redirected_to trip_path(trip, anchor: "itinerary")
    post trip_stays_path(trip), params: { stay: { location: "McCall", kind: "hotel",
      booking_status: "planned", check_in: "2026-09-12", check_out: "2026-09-30" } }
    post trip_legs_path(trip), params: { trip_leg: { kind: "flight", starts_on: "2026-09-01",
      origin: "AUS", destination: "BOI", booking_status: "booked" } }

    get trip_path(trip)
    assert_match "Airbnb in Boise", response.body
    assert_match "Flight · AUS → BOI", response.body
    assert_match "Not booked", response.body
    assert_match "Nights with nowhere to sleep", response.body
    assert_match "Sep 10 – Sep 11", response.body
  end

  test "a companion can see the trip and edit the itinerary; an outsider can do neither" do
    trip = create_trip
    stay = trip.stays.create!(location: "Boise", check_in: "2026-09-01", check_out: "2026-09-30")
    trip.memberships.create!(user: users(:two))

    sign_in_as users(:two)
    get trip_path(trip)
    assert_response :success
    patch stay_path(stay), params: { stay: { booking_status: "booked", location: stay.location,
      kind: stay.kind, check_in: stay.check_in, check_out: stay.check_out } }
    assert stay.reload.booked?

    # The trip itself stays the owner's: no renaming, no deleting.
    patch trip_path(trip), params: { trip: { name: "Mine now" } }
    assert_response :not_found

    sign_in_as users(:outsider)
    get trip_path(trip)
    assert_response :not_found
    patch stay_path(stay), params: { stay: { location: "Nope" } }
    assert_response :not_found
  end

  test "stays and legs can be reworked and removed as plans change" do
    trip = create_trip
    stay = trip.stays.create!(location: "Boise", check_in: "2026-09-01", check_out: "2026-09-30")
    leg = trip.legs.create!(kind: "flight", starts_on: "2026-09-01", origin: "AUS", destination: "BOI")

    get new_trip_stay_path(trip)
    assert_response :success
    get edit_stay_path(stay)
    assert_response :success
    get edit_leg_path(leg)
    assert_response :success

    patch leg_path(leg), params: { trip_leg: { kind: "flight", starts_on: "2026-09-02",
      origin: "AUS", destination: "BOI", booking_status: "booked" } }
    assert_redirected_to trip_path(trip, anchor: "itinerary")
    assert leg.reload.booked?
    assert_equal Date.new(2026, 9, 2), leg.starts_on

    assert_difference("Stay.count", -1) { delete stay_path(stay) }
    assert_difference("TripLeg.count", -1) { delete leg_path(leg) }
  end

  test "a new stay's check-in defaults to where the last one ended" do
    trip = create_trip
    trip.stays.create!(location: "Boise", check_in: "2026-09-01", check_out: "2026-09-10")

    get new_trip_stay_path(trip)
    assert_select "input[name='stay[check_in]'][value='2026-09-10']"
  end

  test "the owner adds and removes companions; a companion can leave" do
    trip = create_trip
    post trip_companions_path(trip), params: { trip_membership: { user_id: users(:two).id } }
    assert trip.reload.traveler?(users(:two))

    sign_in_as users(:two)
    membership = trip.memberships.sole
    delete trip_companion_path(membership)
    assert_not trip.reload.traveler?(users(:two))
  end

  test "someone outside the household can't be added" do
    trip = create_trip
    assert_no_difference("TripMembership.count") do
      post trip_companions_path(trip), params: { trip_membership: { user_id: users(:outsider).id } }
    end
    assert_response :not_found
  end

  test "comments are shared among travelers, and removal is author-or-owner" do
    trip = create_trip
    trip.memberships.create!(user: users(:two))
    post trip_comments_path(trip), params: { trip_comment: { body: "Host says park around back" } }

    sign_in_as users(:two)
    get trip_path(trip)
    assert_match "park around back", response.body
    post trip_comments_path(trip), params: { trip_comment: { body: "Booked the hot springs" } }

    sign_in_as users(:outsider)
    assert_no_difference("TripComment.count") do
      post trip_comments_path(trip), params: { trip_comment: { body: "Let me in" } }
    end
    assert_response :not_found

    sign_in_as users(:one)
    others = trip.comments.find_by!(user: users(:two))
    assert_difference("TripComment.count", -1) { delete trip_comment_path(others) }
  end

  test "the itinerary draws its route once stays name real places" do
    trip = create_trip(starts_on: "2026-09-01", ends_on: "2026-10-31")
    trip.stays.create!(location: "Boise", check_in: "2026-09-01", check_out: "2026-10-01",
      booking_status: "booked")
    trip.stays.create!(location: "Portland", check_in: "2026-10-01", check_out: "2026-10-31")

    get trip_path(trip)
    assert_response :success
    assert_match "The route", response.body
    assert_select "a[title*='Boise']", minimum: 1
    assert_select "line", count: 1
  end

  test "the itinerary card totals what's booked and what's still to book" do
    trip = create_trip
    trip.stays.create!(location: "Boise", check_in: "2026-09-01", check_out: "2026-10-31",
      booking_status: "booked", cost: "1850")
    trip.legs.create!(kind: "car_rental", starts_on: "2026-09-01", booking_status: "planned", cost: "420.50")

    get trip_path(trip)
    assert_match "Booked:", response.body
    assert_match "$1,850.00", response.body
    assert_match "Still to book:", response.body
    assert_match "$420.50", response.body
  end

  test "the trips index groups by phase" do
    create_trip(name: "Ahead", starts_on: "2026-09-01", ends_on: "2026-10-31")
    create_trip(name: "Now", starts_on: "2026-06-01", ends_on: "2026-06-30")
    create_trip(name: "Behind", starts_on: "2026-01-01", ends_on: "2026-01-31")

    get trips_path
    assert_response :success
    assert_match "Coming up", response.body
    assert_match "Underway", response.body
    assert_match "Been and back", response.body
  end

  private
    def create_trip(name: "Santa Fe", starts_on: "2026-09-01", ends_on: "2026-10-31")
      users(:one).trips.create!(name:, starts_on:, ends_on:)
    end
end
