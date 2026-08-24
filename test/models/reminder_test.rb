require "test_helper"

# D-reminders: user-armed scheduled delivery. The rules worth pinning are
# the ones that make a reminder trustworthy — it fires once, at the right
# local time, and it follows the thing it hangs on when that moves.
class ReminderTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.household.update!(time_zone: "America/Chicago")
    @zone = @user.household.zone
  end

  # Events compose their schedule in Time.zone, which ApplicationController
  # sets to the household's zone for the length of a request. Model tests
  # run outside that, so "2pm" would otherwise mean 2pm UTC.
  def create_event(**attributes) = Time.use_zone(@zone) { @user.events.create!(**attributes) }
  def update_event(event, **attributes) = Time.use_zone(@zone) { event.update!(**attributes) }

  test "an absolute reminder is composed in the household's zone, not the box's" do
    reminder = @user.reminders.create!(body: "Call the pharmacy",
      deliver_on: Date.current + 1, deliver_time: "16:00")

    assert_equal 16, reminder.deliver_at.in_time_zone(@zone).hour
    assert_equal "4:00 PM", reminder.local_deliver_at.strftime("%-l:%M %p")
  end

  test "a day with no time means the morning, not midnight" do
    reminder = @user.reminders.create!(body: "Call the pharmacy", deliver_on: Date.current + 1)

    assert_equal Reminder::DEFAULT_HOUR, reminder.local_deliver_at.hour
  end

  test "a relative reminder counts back from the event it hangs on" do
    event = create_event(title: "Dentist", starts_date: Date.current + 2, starts_time: "14:00")
    reminder = @user.reminders.create!(subject: event, lead_minutes: 60)

    assert_equal event.starts_at - 1.hour, reminder.deliver_at
    assert_equal "Dentist", reminder.body, "the body defaults to the item's title"
  end

  test "moving the event moves the reminder with it" do
    event = create_event(title: "Dentist", starts_date: Date.current + 2, starts_time: "14:00")
    reminder = @user.reminders.create!(subject: event, lead_minutes: 60)

    update_event(event, starts_time: "16:00")

    assert_equal event.reload.starts_at - 1.hour, reminder.reload.deliver_at
  end

  test "an absolute reminder stays put when its event moves" do
    event = create_event(title: "Dentist", starts_date: Date.current + 2, starts_time: "14:00")
    reminder = @user.reminders.create!(subject: event, deliver_on: Date.current + 1, deliver_time: "09:00")
    original = reminder.deliver_at

    update_event(event, starts_time: "16:00")

    assert_equal original, reminder.reload.deliver_at
  end

  test "a relative reminder retires when the date it counted back from is gone" do
    task = @user.tasks.create!(title: "File the appeal", due_on: Date.current + 3)
    reminder = @user.reminders.create!(subject: task, lead_minutes: 1440)

    task.update!(due_on: nil)

    assert_not Reminder.exists?(reminder.id), "there is no moment left to fire at"
  end

  test "an all-day event counts back from the start of the day, not midnight" do
    event = create_event(title: "Anniversary", starts_date: Date.current + 2)
    assert event.all_day?

    reminder = @user.reminders.create!(subject: event, lead_minutes: 60)

    assert_equal Remindable::DAY_START_HOUR - 1, reminder.local_deliver_at.hour
  end

  test "a task with no due date can still carry an absolute reminder" do
    task = @user.tasks.create!(title: "Call the landlord")
    assert_nil task.remind_from

    reminder = @user.reminders.create!(subject: task, deliver_on: Date.current + 1, deliver_time: "10:00")

    assert_equal 10, reminder.local_deliver_at.hour
  end

  test "the message is code-built from the user's own words and a clock reading" do
    event = create_event(title: "Dentist", starts_date: Date.current + 1, starts_time: "14:00")
    reminder = @user.reminders.create!(subject: event, lead_minutes: 60)

    assert_equal "Reminder: Dentist — tomorrow at 2:00 PM", reminder.message
  end

  test "a standalone reminder's message is just what the user wrote" do
    reminder = @user.reminders.create!(body: "Call the pharmacy", deliver_on: Date.current + 1)

    assert_equal "Reminder: Call the pharmacy", reminder.message
  end

  test "a reminder cannot be set in the past, or on someone else's item" do
    assert_not @user.reminders.new(body: "Too late", deliver_on: Date.current - 1).valid?

    other_event = users(:two).events.create!(title: "Theirs", starts_date: Date.current + 1, starts_time: "09:00")
    assert_not @user.reminders.new(subject: other_event, lead_minutes: 60).valid?
  end

  test "deleting the item takes its reminders with it" do
    event = create_event(title: "Dentist", starts_date: Date.current + 2, starts_time: "14:00")
    @user.reminders.create!(subject: event, lead_minutes: 60)

    assert_difference -> { Reminder.count }, -1 do
      event.destroy!
    end
  end
end
