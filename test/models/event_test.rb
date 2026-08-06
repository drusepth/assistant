require "test_helper"

class EventTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  test "a date alone makes an all-day event" do
    event = @user.events.create!(title: "Vacation day", starts_date: "2026-08-10")

    assert event.all_day?
    assert_equal Time.zone.local(2026, 8, 10), event.starts_at
    assert_nil event.ends_at
  end

  test "a start time makes a timed event, with optional end" do
    event = @user.events.create!(
      title: "Dentist", starts_date: "2026-08-10", starts_time: "15:00", ends_time: "15:30"
    )

    assert_not event.all_day?
    assert_equal Time.zone.local(2026, 8, 10, 15, 0), event.starts_at
    assert_equal Time.zone.local(2026, 8, 10, 15, 30), event.ends_at
  end

  test "clearing the start time flips a timed event back to all-day" do
    event = @user.events.create!(title: "Dentist", starts_date: "2026-08-10", starts_time: "15:00")

    event.update!(starts_date: "2026-08-10", starts_time: "", ends_time: "")

    assert event.reload.all_day?
    assert_equal Time.zone.local(2026, 8, 10), event.starts_at
  end

  test "virtual parts read back from the stored schedule" do
    event = @user.events.create!(title: "Dentist", starts_date: "2026-08-10", starts_time: "15:00", ends_time: "16:00")
    fresh = Event.find(event.id)

    assert_equal Date.new(2026, 8, 10), fresh.starts_date
    assert_equal "15:00", fresh.starts_time
    assert_equal "16:00", fresh.ends_time
  end

  test "edits that don't touch the schedule leave it alone" do
    event = @user.events.create!(title: "Dentist", starts_date: "2026-08-10", starts_time: "15:00")

    Event.find(event.id).update!(title: "Dentist — rescheduled?")

    assert_equal Time.zone.local(2026, 8, 10, 15, 0), event.reload.starts_at
    assert_not event.all_day?
  end

  test "direct writes to starts_at pass through untouched" do
    event = @user.events.create!(title: "Quick", starts_date: "2026-08-10")

    Event.find(event.id).update!(starts_at: Time.zone.local(2026, 8, 10, 9, 0), all_day: false)

    assert_equal Time.zone.local(2026, 8, 10, 9, 0), event.reload.starts_at
  end
end
