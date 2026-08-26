require "test_helper"

module Travel
  class OutlookTest < ActiveSupport::TestCase
    TODAY = Date.new(2026, 6, 15)

    setup { @user = users(:one) }

    test "knows the stay you're inside and the moves ahead, in order" do
      trip = @user.trips.create!(name: "Idaho", starts_on: "2026-06-01", ends_on: "2026-08-31")
      current = trip.stays.create!(location: "Boise", check_in: "2026-06-01", check_out: "2026-07-01",
        booking_status: "booked")
      next_stay = trip.stays.create!(location: "McCall", check_in: "2026-07-01", check_out: "2026-08-31",
        booking_status: "booked")
      drive = trip.legs.create!(kind: "drive", starts_on: "2026-07-01", booking_status: "booked")

      outlook = Outlook.new(@user, today: TODAY)
      assert_equal current, outlook.current_stay
      assert_equal [ drive, next_stay ], outlook.next_moves
    end

    test "an unbooked stay inside the lead time is a warning; beyond it, still just a plan" do
      trip = @user.trips.create!(name: "Idaho", starts_on: "2026-06-01", ends_on: "2026-12-31")
      trip.stays.create!(location: "Boise", check_in: "2026-06-01", check_out: "2026-07-10",
        booking_status: "booked")
      trip.stays.create!(location: "McCall", check_in: "2026-07-10", check_out: "2026-09-01",
        booking_status: "planned")
      trip.stays.create!(location: "Ketchum", check_in: "2026-09-01", check_out: "2026-12-31",
        booking_status: "planned")

      messages = Outlook.new(@user, today: TODAY).warnings.map(&:message)
      assert messages.any? { |m| m.include?("McCall") }, "the near unbooked stay warns: #{messages}"
      assert messages.none? { |m| m.include?("Ketchum") }, "the far one doesn't: #{messages}"
    end

    test "uncovered nights inside the lead time warn, and a bookless drive never does" do
      trip = @user.trips.create!(name: "Idaho", starts_on: "2026-06-01", ends_on: "2026-07-31")
      trip.stays.create!(location: "Boise", check_in: "2026-06-01", check_out: "2026-06-20",
        booking_status: "booked")
      trip.stays.create!(location: "McCall", check_in: "2026-06-23", check_out: "2026-07-31",
        booking_status: "booked")
      trip.legs.create!(kind: "drive", starts_on: "2026-06-20", booking_status: "planned")

      messages = Outlook.new(@user, today: TODAY).warnings.map(&:message)
      assert messages.any? { |m| m.include?("nowhere to sleep") }, messages.inspect
      assert messages.none? { |m| m.include?("Drive") }, messages.inspect
    end

    test "covers trips you were added to, not only your own" do
      trip = users(:two).trips.create!(name: "Shared", starts_on: "2026-06-01", ends_on: "2026-07-31")
      trip.memberships.create!(user: @user)
      stay = trip.stays.create!(location: "Boise", check_in: "2026-06-01", check_out: "2026-07-31",
        booking_status: "booked")

      assert_equal stay, Outlook.new(@user, today: TODAY).current_stay
    end

    test "two stays claiming the same night is a double booking, and it warns" do
      trip = @user.trips.create!(name: "Idaho", starts_on: "2026-06-01", ends_on: "2026-08-31")
      trip.stays.create!(location: "Boise", check_in: "2026-07-01", check_out: "2026-07-10",
        booking_status: "booked")
      trip.stays.create!(location: "McCall", check_in: "2026-07-08", check_out: "2026-07-20",
        booking_status: "booked")

      messages = Outlook.new(@user, today: TODAY).warnings.map(&:message)
      assert messages.any? { |m| m.include?("Double-booked") && m.include?("Jul 8 – Jul 9") }, messages.inspect
    end

    test "an overlap already behind you doesn't warn" do
      trip = @user.trips.create!(name: "Idaho", starts_on: "2026-06-01", ends_on: "2026-08-31")
      trip.stays.create!(location: "Boise", check_in: "2026-06-01", check_out: "2026-06-05")
      trip.stays.create!(location: "McCall", check_in: "2026-06-03", check_out: "2026-06-08")

      messages = Outlook.new(@user, today: TODAY).warnings.map(&:message)
      assert messages.none? { |m| m.include?("Double-booked") }, messages.inspect
    end

    test "the nights between two chained trips warn — the drive never has to be its own trip" do
      first = @user.trips.create!(name: "Idaho", starts_on: "2026-05-01", ends_on: "2026-06-30")
      first.stays.create!(location: "Boise", check_in: "2026-05-01", check_out: "2026-06-30",
        booking_status: "booked")
      second = @user.trips.create!(name: "New Mexico", starts_on: "2026-07-03", ends_on: "2026-08-31")
      second.stays.create!(location: "Santa Fe", check_in: "2026-07-03", check_out: "2026-08-31",
        booking_status: "booked")

      messages = Outlook.new(@user, today: TODAY).warnings.map(&:message)
      assert messages.any? { |m| m.include?("between Idaho and New Mexico") && m.include?("3 nights") },
        messages.inspect

      # A road stay on either trip covers the drive and clears the warning.
      first.stays.create!(location: "Salt Lake City", check_in: "2026-06-30", check_out: "2026-07-03",
        booking_status: "booked")
      assert Outlook.new(@user, today: TODAY).warnings.none? { |w| w.message.include?("between Idaho") }
    end

    test "a real break between trips is going home, not a gap" do
      first = @user.trips.create!(name: "Idaho", starts_on: "2026-05-01", ends_on: "2026-06-20")
      first.stays.create!(location: "Boise", check_in: "2026-05-01", check_out: "2026-06-20")
      second = @user.trips.create!(name: "New Mexico", starts_on: "2026-07-15", ends_on: "2026-08-31")
      second.stays.create!(location: "Santa Fe", check_in: "2026-07-15", check_out: "2026-08-31")

      messages = Outlook.new(@user, today: TODAY).warnings.map(&:message)
      assert messages.none? { |m| m.include?("between") }, messages.inspect
    end

    test "a past trip contributes nothing" do
      trip = @user.trips.create!(name: "Done", starts_on: "2026-01-01", ends_on: "2026-02-01")
      trip.stays.create!(location: "Old", check_in: "2026-01-01", check_out: "2026-02-01",
        booking_status: "planned")

      outlook = Outlook.new(@user, today: TODAY)
      assert_nil outlook.current_stay
      assert_empty outlook.next_moves
      assert_empty outlook.warnings
    end
  end
end
