require "test_helper"

class TripMembershipTest < ActiveSupport::TestCase
  setup do
    @trip = users(:one).trips.create!(name: "Boise", starts_on: "2026-09-01", ends_on: "2026-09-30")
  end

  test "a companion must share the owner's household" do
    assert @trip.memberships.new(user: users(:two)).valid?
    assert_not @trip.memberships.new(user: users(:outsider)).valid?
  end

  test "the owner isn't a companion, and nobody joins twice" do
    assert_not @trip.memberships.new(user: users(:one)).valid?

    @trip.memberships.create!(user: users(:two))
    assert_not @trip.memberships.new(user: users(:two)).valid?
  end
end
