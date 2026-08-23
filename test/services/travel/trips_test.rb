require "test_helper"

class Travel::TripsTest < ActiveSupport::TestCase
  HOME = [ 51.5072, -0.1276 ]   # London
  LISBON = [ 38.7223, -9.1393 ]
  PORTO = [ 41.1579, -8.6291 ]
  TOKYO = [ 35.6762, 139.6503 ]
  BRIGHTON = [ 50.8225, -0.1372 ] # 75km from home — a day out, not a trip

  test "a run of days away from home is a trip, named for where it was" do
    live_at_home
    3.times { |day| place(LISBON, on: Date.new(2024, 3, 10 + day)) }

    candidate = detect.candidates.sole

    assert_equal Date.new(2024, 3, 10), candidate.starts_on
    assert_equal Date.new(2024, 3, 12), candidate.ends_on
    assert_equal 3, candidate.photo_count
    assert_equal 3, candidate.days
    assert_equal "Lisbon", candidate.suggested_name
    assert_equal "Lisbon, Portugal", candidate.place_label
  end

  test "home is where the most days are, not where the most photos are" do
    # One wildly-photographed weekend away must not become "home".
    live_at_home
    40.times { |n| place(LISBON, on: Date.new(2024, 3, 10), minute: n) }
    place(LISBON, on: Date.new(2024, 3, 11))

    assert_in_delta HOME.first, detect.home.latitude, 0.5
    assert_equal 1, detect.candidates.size
  end

  test "two cities on one trip are one trip, named for the country" do
    live_at_home
    3.times { |day| place(LISBON, on: Date.new(2024, 3, 10 + day)) }
    3.times { |day| place(PORTO, on: Date.new(2024, 3, 13 + day)) }

    candidate = detect.candidates.sole

    assert_equal Date.new(2024, 3, 10)..Date.new(2024, 3, 15), candidate.starts_on..candidate.ends_on
    assert_equal "Portugal", candidate.suggested_name
  end

  test "a gap of a few quiet days holds a trip together, a long one splits it" do
    live_at_home
    2.times { |day| place(TOKYO, on: Date.new(2024, 5, 1 + day)) }
    place(TOKYO, on: Date.new(2024, 5, 6)) # 3 days later — same trip
    3.times { |day| place(TOKYO, on: Date.new(2024, 9, 1 + day)) } # months later

    starts = detect.candidates.map(&:starts_on).sort

    assert_equal [ Date.new(2024, 5, 1), Date.new(2024, 9, 1) ], starts
  end

  test "a day out near home is not a trip" do
    live_at_home
    4.times { |n| place(BRIGHTON, on: Date.new(2024, 4, 6), minute: n) }

    assert_empty detect.candidates
  end

  test "one afternoon abroad is not a trip either" do
    live_at_home
    5.times { |n| place(LISBON, on: Date.new(2024, 3, 10), minute: n) }

    assert_empty detect.candidates
  end

  test "a library with no home has no trips to find" do
    assert_empty detect.candidates
  end

  test "a saved trip keeps its own photos, and gains ones added later" do
    live_at_home
    3.times { |day| place(LISBON, on: Date.new(2024, 3, 10 + day)) }
    at_home = place(HOME, on: Date.new(2024, 3, 11))

    trip = users(:one).trips.from_candidate(detect.candidates.sole)
    trip.save!

    assert_equal 3, trip.photos.count
    assert_not_includes trip.photos, at_home, "home photos from the same days aren't the trip"

    later = place(LISBON, on: Date.new(2024, 3, 11), minute: 30)
    assert_includes trip.reload.photos, later
  end

  private
    def detect = Travel::Trips.new(Photos::Map.new(users(:one).photos))

    # Enough ordinary days at home for home to be obvious.
    def live_at_home
      20.times { |day| place(HOME, on: Date.new(2024, 1, 1) + day) }
    end

    def place((latitude, longitude), on:, minute: 0)
      users(:one).photos.create!(
        image: { io: File.open(file_fixture("photo.jpg")), filename: "photo.jpg", content_type: "image/jpeg" },
        latitude: latitude, longitude: longitude, taken_at: on.to_time + (12.hours + minute.minutes)
      )
    end
end
