require "test_helper"

class TripsControllerTest < ActionDispatch::IntegrationTest
  HOME = [ 51.5072, -0.1276 ]
  LISBON = [ 38.7223, -9.1393 ]

  setup { sign_in_as users(:one) }

  test "the hub offers the trips it found, and keeping one saves it" do
    live_at_home
    3.times { |day| place(LISBON, on: Date.new(2024, 3, 10 + day)) }

    get section_path("travel")
    assert_response :success
    assert_match "Trips in your photos", response.body
    assert_match "Lisbon", response.body

    assert_difference("Trip.count", 1) do
      post trips_path, params: { trip: { source: "photos", starts_on: "2024-03-10", name: "Lisbon" } }
    end
    trip = Trip.sole
    assert_redirected_to trip
    assert_equal "Lisbon", trip.name
    assert_equal users(:one), trip.user
    assert_equal Date.new(2024, 3, 12), trip.ends_on
  end

  test "a kept trip stops being offered again" do
    live_at_home
    3.times { |day| place(LISBON, on: Date.new(2024, 3, 10 + day)) }
    post trips_path, params: { trip: { source: "photos", starts_on: "2024-03-10" } }

    get section_path("travel")
    assert_match "Your trips", response.body
    assert_no_match "Trips in your photos", response.body
  end

  test "the stored trip is recomputed here, never taken from the form" do
    live_at_home
    3.times { |day| place(LISBON, on: Date.new(2024, 3, 10 + day)) }

    post trips_path, params: { trip: { source: "photos", starts_on: "2024-03-10", name: "Somewhere else",
      south: "-89", west: "-179", north: "89", east: "179", ends_on: "2030-01-01" } }

    trip = Trip.sole
    assert_equal Date.new(2024, 3, 12), trip.ends_on, "the form doesn't get to set the dates"
    assert_in_delta LISBON.first, trip.south.to_f, 0.5, "nor the box"
  end

  test "a trip the photos no longer support can't be saved" do
    live_at_home

    assert_no_difference("Trip.count") do
      post trips_path, params: { trip: { source: "photos", starts_on: "2019-01-01" } }
    end
    assert_redirected_to section_path("travel")
    assert_match "isn't in your photos", flash[:alert]
  end

  test "the trip page shows its photos, its own zoomed map, and events from those days" do
    live_at_home
    photos = 3.times.map { |day| place(LISBON, on: Date.new(2024, 3, 10 + day)) }
    at_home = place(HOME, on: Date.new(2024, 3, 11))
    during = users(:one).events.create!(title: "Flight home", starts_at: Time.zone.local(2024, 3, 12, 18))
    after = users(:one).events.create!(title: "Dentist", starts_at: Time.zone.local(2024, 4, 2, 9))
    post trips_path, params: { trip: { source: "photos", starts_on: "2024-03-10" } }

    get trip_path(Trip.sole)
    assert_response :success
    assert_select "a[href=?]", photo_path(photos.first)
    assert_select "a[href=?]", photo_path(at_home), count: 0
    assert_match "Flight home", response.body
    assert_no_match "Dentist", response.body
    # Zoomed: the viewBox is a window on the world, not the whole of it.
    assert_select "svg[viewBox]" do |elements|
      assert_operator elements.first["viewBox"].split.third.to_f, :<, Photos::Map::WIDTH
    end
  end

  test "trips are owner-only" do
    live_at_home
    3.times { |day| place(LISBON, on: Date.new(2024, 3, 10 + day)) }
    post trips_path, params: { trip: { source: "photos", starts_on: "2024-03-10" } }
    trip = Trip.sole

    sign_in_as users(:two)
    get trip_path(trip)
    assert_response :not_found

    patch trip_path(trip), params: { trip: { name: "Mine now" } }
    assert_response :not_found
    assert_no_difference("Trip.count") { delete trip_path(trip) }
  end

  test "renaming and removing leave the photos alone" do
    live_at_home
    3.times { |day| place(LISBON, on: Date.new(2024, 3, 10 + day)) }
    post trips_path, params: { trip: { source: "photos", starts_on: "2024-03-10" } }
    trip = Trip.sole

    patch trip_path(trip), params: { trip: { name: "Portugal, at last" } }
    assert_equal "Portugal, at last", trip.reload.name

    assert_no_difference("Photo.count") { delete trip_path(trip) }
    assert_redirected_to section_path("travel")
  end

  test "a planned trip whose dates have photos can earn its box" do
    live_at_home
    3.times { |day| place(LISBON, on: Date.new(2024, 3, 10 + day)) }
    trip = users(:one).trips.create!(name: "Lisbon, planned ahead",
      starts_on: "2024-03-09", ends_on: "2024-03-14")

    get trip_path(trip)
    assert_match "Give this trip its map", response.body

    post place_trip_path(trip)
    assert_redirected_to trip
    trip.reload
    assert trip.placed?
    assert_in_delta LISBON.first, trip.south.to_f, 0.5
    assert_equal 3, trip.photos.count, "its photos attach the moment it's placed"
    assert trip.cover_photo_id.present?
  end

  test "placing is owner-only and needs photos to place from" do
    live_at_home
    trip = users(:one).trips.create!(name: "Nowhere yet", starts_on: "2024-03-09", ends_on: "2024-03-14")

    get trip_path(trip)
    assert_no_match "Give this trip its map", response.body

    post place_trip_path(trip)
    assert_redirected_to trip
    assert_not trip.reload.placed?
    assert_match "carry a location", flash[:alert]

    trip.memberships.create!(user: users(:two))
    sign_in_as users(:two)
    post place_trip_path(trip)
    assert_response :not_found
  end

  private
    def live_at_home
      20.times { |day| place(HOME, on: Date.new(2024, 1, 1) + day) }
    end

    def place((latitude, longitude), on:)
      users(:one).photos.create!(
        image: { io: File.open(file_fixture("photo.jpg")), filename: "photo.jpg", content_type: "image/jpeg" },
        latitude: latitude, longitude: longitude, taken_at: on.to_time + 12.hours
      )
    end
end
