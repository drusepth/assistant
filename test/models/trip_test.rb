require "test_helper"

class TripTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    travel_to Time.zone.local(2026, 6, 15, 12)
    @user = users(:one)
  end

  teardown { travel_back }

  test "a planned trip needs no box, and a partial box is rejected" do
    trip = @user.trips.new(name: "Santa Fe", starts_on: "2026-09-01", ends_on: "2026-10-31")
    assert trip.valid?
    assert_not trip.placed?

    trip.south = 35.0
    assert_not trip.valid?
    assert_match(/all four edges/, trip.errors.full_messages.to_sentence)
  end

  test "a planned trip derives no photos until it has a box" do
    trip = @user.trips.create!(name: "Santa Fe", starts_on: "2026-09-01", ends_on: "2026-10-31")
    assert_empty trip.photos
  end

  test "phase follows the dates" do
    upcoming = @user.trips.create!(name: "Next", starts_on: "2026-07-01", ends_on: "2026-08-31")
    underway = @user.trips.create!(name: "Now", starts_on: "2026-06-01", ends_on: "2026-07-31")
    past = @user.trips.create!(name: "Then", starts_on: "2026-01-01", ends_on: "2026-02-28")

    assert upcoming.upcoming?
    assert underway.underway?
    assert past.past?
  end

  test "the timeline runs chronologically, legs before stays on a shared day" do
    trip = @user.trips.create!(name: "Boise", starts_on: "2026-09-01", ends_on: "2026-09-30")
    stay = trip.stays.create!(location: "Boise", check_in: "2026-09-01", check_out: "2026-09-30")
    flight = trip.legs.create!(kind: "flight", starts_on: "2026-09-01")

    assert_equal [ flight, stay ], trip.timeline
  end

  test "lodging gaps are the uncovered nights, and back-to-back stays leave none" do
    trip = @user.trips.create!(name: "Two towns", starts_on: "2026-09-01", ends_on: "2026-09-11")
    trip.stays.create!(location: "One", check_in: "2026-09-01", check_out: "2026-09-05")
    trip.stays.create!(location: "Two", check_in: "2026-09-05", check_out: "2026-09-09")

    gaps = trip.lodging_gaps
    assert_equal 1, gaps.size
    assert_equal Date.new(2026, 9, 9)..Date.new(2026, 9, 10), gaps.first
  end

  test "a trip with no stays is one whole gap" do
    trip = @user.trips.create!(name: "Bare", starts_on: "2026-09-01", ends_on: "2026-09-04")
    assert_equal [ Date.new(2026, 9, 1)..Date.new(2026, 9, 3) ], trip.lodging_gaps
  end

  test "a drive in your own car never counts as unbooked" do
    trip = @user.trips.create!(name: "Road", starts_on: "2026-09-01", ends_on: "2026-09-30")
    trip.legs.create!(kind: "drive", starts_on: "2026-09-01", booking_status: "planned")
    rental = trip.legs.create!(kind: "car_rental", starts_on: "2026-09-02", booking_status: "planned")
    stay = trip.stays.create!(location: "Boise", check_in: "2026-09-01", check_out: "2026-09-30",
      booking_status: "planned")

    assert_equal [ rental ], trip.unbooked_legs
    assert_equal [ stay ], trip.unbooked_stays
  end

  test "involving finds owned trips and joined trips, and nothing else" do
    own = @user.trips.create!(name: "Mine", starts_on: "2026-09-01", ends_on: "2026-09-30")
    joined = users(:two).trips.create!(name: "Theirs", starts_on: "2026-10-01", ends_on: "2026-10-31")
    joined.memberships.create!(user: @user)
    users(:two).trips.create!(name: "Not mine", starts_on: "2026-11-01", ends_on: "2026-11-30")

    assert_equal [ own, joined ].sort_by(&:id), Trip.involving(@user).sort_by(&:id)
  end

  test "travelers and traveler? cover the owner and the companions" do
    trip = @user.trips.create!(name: "Shared", starts_on: "2026-09-01", ends_on: "2026-09-30")
    trip.memberships.create!(user: users(:two))

    assert_equal [ @user, users(:two) ], trip.travelers
    assert trip.traveler?(users(:two))
    assert_not trip.traveler?(users(:outsider))
  end
end
