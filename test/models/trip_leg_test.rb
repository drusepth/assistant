require "test_helper"

class TripLegTest < ActiveSupport::TestCase
  setup do
    @trip = users(:one).trips.create!(name: "Boise", starts_on: "2026-09-01", ends_on: "2026-09-30")
  end

  test "the display name uses what it has" do
    assert_equal "Flight · AUS → BOI",
      @trip.legs.new(kind: "flight", origin: "AUS", destination: "BOI").display_name
    assert_equal "Drive to Boise", @trip.legs.new(kind: "drive", destination: "Boise").display_name
    assert_equal "Car rental · Hertz", @trip.legs.new(kind: "car_rental", carrier: "Hertz").display_name
    assert_equal "Train", @trip.legs.new(kind: "train").display_name
  end

  test "a rental's drop-off can't precede its pick-up" do
    leg = @trip.legs.new(kind: "car_rental", starts_on: "2026-09-10", ends_on: "2026-09-09")
    assert_not leg.valid?
  end

  test "the period covers a range only when there is one" do
    assert_equal "10 Sep", @trip.legs.new(starts_on: "2026-09-10").period
    assert_equal "10 Sep – 20 Sep", @trip.legs.new(starts_on: "2026-09-10", ends_on: "2026-09-20").period
  end
end
