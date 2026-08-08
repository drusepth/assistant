require "test_helper"

class HouseholdTest < ActiveSupport::TestCase
  setup { @household = households(:smith) }

  test "the address is a free-text block, read back as clean lines" do
    @household.update!(address: "  123 Maple Street\n\nApt 4B  \nAustin, TX 78701\n")

    assert_equal [ "123 Maple Street", "Apt 4B", "Austin, TX 78701" ], @household.address_lines
    assert_empty Household.new.address_lines
  end

  test "the zone accepts both the friendly and the IANA spelling" do
    @household.update!(time_zone: "Central Time (US & Canada)")
    assert_equal "America/Chicago", @household.zone.tzinfo.name

    @household.update!(time_zone: "America/New_York")
    assert_equal "America/New_York", @household.zone.tzinfo.name
  end

  test "a blank zone falls back to the instance default" do
    assert_equal Time.zone, @household.zone
  end

  test "an unknown zone is a validation error" do
    @household.time_zone = "Middle Earth"

    assert_not @household.valid?
    assert_includes @household.errors[:time_zone], "isn't a time zone I recognize"
  end

  test "home_status is one of three, or nothing" do
    assert Household.new(name: "x", home_status: "rent").valid?
    assert Household.new(name: "x", home_status: nil).valid?
    assert_not Household.new(name: "x", home_status: "squatting").valid?
  end

  test "years at home counts whole years and ignores the future" do
    @household.update!(moved_in_on: Date.new(2019, 6, 15))

    assert_equal 7, @household.years_at_home(on: Date.new(2026, 6, 15))
    assert_equal 6, @household.years_at_home(on: Date.new(2026, 6, 14))
    assert_nil @household.years_at_home(on: Date.new(2019, 1, 1))
  end

  test "the anniversary is the day, and never the move-in day itself" do
    @household.update!(moved_in_on: Date.new(2019, 6, 15))

    assert @household.home_anniversary?(on: Date.new(2026, 6, 15))
    assert_not @household.home_anniversary?(on: Date.new(2026, 6, 16))
    assert_not @household.home_anniversary?(on: Date.new(2019, 6, 15))
  end

  test "profile_complete? ignores the name every household already has" do
    assert_not @household.profile_complete?

    @household.update!(phone: "(512) 555-0142")
    assert @household.profile_complete?
  end
end
