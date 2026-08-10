require "test_helper"

class EventTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    travel_to Time.zone.local(2026, 8, 6, 12)
    @user = users(:one)
  end

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

  test "overlapping includes events spanning the range" do
    today = Time.current.beginning_of_day..Time.current.end_of_day
    ongoing = users(:one).events.create!(title: "Trip", starts_at: 2.days.ago, ends_at: 2.days.from_now)
    later_today = users(:one).events.create!(title: "Dinner", starts_at: Time.current + 6.hours)
    next_week = users(:one).events.create!(title: "Far off", starts_at: 6.days.from_now)

    found = Event.overlapping(today)
    assert_includes found, ongoing
    assert_includes found, later_today
    assert_not_includes found, next_week
  end

  test "finished? is based on end time, or start time when no end" do
    assert users(:one).events.create!(title: "Done", starts_at: 3.hours.ago, ends_at: 1.hour.ago).finished?
    assert_not users(:one).events.create!(title: "Running", starts_at: 1.hour.ago, ends_at: 1.hour.from_now).finished?
    assert users(:one).events.create!(title: "Started", starts_at: 1.hour.ago).finished?
  end

  test "finished? treats all-day events as lasting until end of day" do
    today_all_day = users(:one).events.create!(title: "Holiday", starts_at: Time.current.beginning_of_day, all_day: true)
    assert_not today_all_day.finished?

    yesterday_all_day = users(:one).events.create!(title: "Past holiday", starts_at: 1.day.ago.beginning_of_day, all_day: true)
    assert yesterday_all_day.finished?
  end

  test "early_morning? flags timed events before 9am only" do
    # Times are built in the app's zone, not the machine's: early_morning? reads
    # starts_at.hour back, so a system-local Date.tomorrow.to_time would shift
    # the hour on any developer machine that isn't already on UTC.
    tomorrow = Time.zone.tomorrow

    assert users(:one).events.create!(title: "Flight", starts_at: tomorrow.beginning_of_day.change(hour: 6)).early_morning?
    assert_not users(:one).events.create!(title: "Lunch", starts_at: tomorrow.noon).early_morning?
    assert_not users(:one).events.create!(title: "Fair", starts_at: tomorrow.beginning_of_day, all_day: true).early_morning?
  end
end
