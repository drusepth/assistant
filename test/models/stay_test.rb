require "test_helper"

class StayTest < ActiveSupport::TestCase
  setup do
    @trip = users(:one).trips.create!(name: "Boise", starts_on: "2026-09-01", ends_on: "2026-09-30")
  end

  test "check-out must come after check-in" do
    stay = @trip.stays.new(location: "Boise", check_in: "2026-09-05", check_out: "2026-09-05")
    assert_not stay.valid?
    assert_match(/after check-in/, stay.errors.full_messages.to_sentence)
  end

  test "coverage is half-open: the check-out night belongs to the next place" do
    stay = @trip.stays.create!(location: "Boise", check_in: "2026-09-01", check_out: "2026-09-05")

    assert stay.covers?(Date.new(2026, 9, 1))
    assert stay.covers?(Date.new(2026, 9, 4))
    assert_not stay.covers?(Date.new(2026, 9, 5))
    assert_equal 4, stay.nights
  end

  test "display name falls back to the kind and the place" do
    stay = @trip.stays.new(location: "Boise", kind: "airbnb")
    assert_equal "Airbnb in Boise", stay.display_name

    stay.name = "The A-frame"
    assert_equal "The A-frame", stay.display_name
  end
end
