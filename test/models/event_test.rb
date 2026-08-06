require "test_helper"

class EventTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup { travel_to Time.zone.local(2026, 8, 6, 12) }

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
    assert users(:one).events.create!(title: "Flight", starts_at: Date.tomorrow.to_time.change(hour: 6)).early_morning?
    assert_not users(:one).events.create!(title: "Lunch", starts_at: Date.tomorrow.noon).early_morning?
    assert_not users(:one).events.create!(title: "Fair", starts_at: Date.tomorrow.to_time, all_day: true).early_morning?
  end
end
