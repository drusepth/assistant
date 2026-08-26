require "test_helper"

module Travel
  class ItineraryMapTest < ActiveSupport::TestCase
    setup do
      @trip = users(:one).trips.create!(name: "West loop", starts_on: "2026-09-01", ends_on: "2026-10-31")
    end

    test "located stays become numbered waypoints in order, joined by a route" do
      @trip.stays.create!(location: "Boise", check_in: "2026-09-01", check_out: "2026-10-01")
      @trip.stays.create!(location: "Portland", check_in: "2026-10-01", check_out: "2026-10-31")
      @trip.stays.create!(location: "The Yurt Nobody Has Heard Of", check_in: "2026-10-31", check_out: "2026-11-02")

      map = ItineraryMap.new(@trip.stays.by_date)
      assert_equal %w[ Boise Portland ], map.waypoints.map(&:label), "the unlocatable stay pins nothing"
      assert_equal 1, map.segments.count
      # Portland is west of Boise, so its x is smaller under plate carrée.
      assert_operator map.waypoints.last.x, :<, map.waypoints.first.x
    end

    test "two stays in the same town draw one line fewer, and the window is a real box" do
      2.times do |index|
        @trip.stays.create!(location: "Boise", check_in: Date.new(2026, 9, 1 + index),
          check_out: Date.new(2026, 9, 2 + index))
      end

      map = ItineraryMap.new(@trip.stays.by_date)
      assert_equal 2, map.waypoints.size
      assert_empty map.segments.to_a
      assert map.zoomed?
      assert_match(/\A[\d.]+ [\d.]+ [\d.]+ [\d.]+\z/, map.view_box)
    end

    test "a trip with no locatable stays draws nothing" do
      @trip.stays.create!(location: "Somewhere Unmapped 123", check_in: "2026-09-01", check_out: "2026-09-05")

      assert_not ItineraryMap.new(@trip.stays.by_date).any?
    end
  end
end
