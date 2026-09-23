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

  # The same trap one argument to the left: a date in these tests is a day on
  # the *user's* calendar, and the box's `Date.current` is a different day
  # from Chicago's for five hours of every night. Reading "tomorrow" off one
  # clock while the model writes it off the other is a suite that fails in
  # the evening and passes by morning.
  def local_today = Time.current.in_time_zone(@zone).to_date

  test "an absolute reminder is composed in the household's zone, not the box's" do
    reminder = @user.reminders.create!(subject: @user.tasks.create!(title: "Call the pharmacy"), body: "Call the pharmacy",
      deliver_on: local_today + 1, deliver_time: "16:00")

    assert_equal 16, reminder.deliver_at.in_time_zone(@zone).hour
    assert_equal "4:00 PM", reminder.local_deliver_at.strftime("%-l:%M %p")
  end

  test "a day with no time means the morning, not midnight" do
    reminder = @user.reminders.create!(subject: @user.tasks.create!(title: "Call the pharmacy"), body: "Call the pharmacy", deliver_on: local_today + 1)

    assert_equal Reminder::DEFAULT_HOUR, reminder.local_deliver_at.hour
  end

  test "a relative reminder counts back from the event it hangs on" do
    event = create_event(title: "Dentist", starts_date: local_today + 2, starts_time: "14:00")
    reminder = @user.reminders.create!(subject: event, lead_minutes: 60)

    assert_equal event.starts_at - 1.hour, reminder.deliver_at
    assert_equal "Dentist", reminder.body, "the body defaults to the item's title"
  end

  test "moving the event moves the reminder with it" do
    event = create_event(title: "Dentist", starts_date: local_today + 2, starts_time: "14:00")
    reminder = @user.reminders.create!(subject: event, lead_minutes: 60)

    update_event(event, starts_time: "16:00")

    assert_equal event.reload.starts_at - 1.hour, reminder.reload.deliver_at
  end

  test "an absolute reminder stays put when its event moves" do
    event = create_event(title: "Dentist", starts_date: local_today + 2, starts_time: "14:00")
    reminder = @user.reminders.create!(subject: event, deliver_on: local_today + 1, deliver_time: "09:00")
    original = reminder.deliver_at

    update_event(event, starts_time: "16:00")

    assert_equal original, reminder.reload.deliver_at
  end

  test "a relative reminder retires when the date it counted back from is gone" do
    task = @user.tasks.create!(title: "File the appeal", due_on: local_today + 3)
    reminder = @user.reminders.create!(subject: task, lead_minutes: 1440)

    task.update!(due_on: nil)

    assert_not Reminder.exists?(reminder.id), "there is no moment left to fire at"
  end

  test "an all-day event counts back from the start of the day, not midnight" do
    event = create_event(title: "Anniversary", starts_date: local_today + 2)
    assert event.all_day?

    reminder = @user.reminders.create!(subject: event, lead_minutes: 60)

    assert_equal Remindable::DAY_START_HOUR - 1, reminder.local_deliver_at.hour
  end

  test "a task with no due date can still carry an absolute reminder" do
    task = @user.tasks.create!(title: "Call the landlord")
    assert_nil task.remind_from

    reminder = @user.reminders.create!(subject: task, deliver_on: local_today + 1, deliver_time: "10:00")

    assert_equal 10, reminder.local_deliver_at.hour
  end

  test "the message is code-built from the user's own words and a clock reading" do
    event = create_event(title: "Dentist", starts_date: local_today + 1, starts_time: "14:00")
    reminder = @user.reminders.create!(subject: event, lead_minutes: 60)

    assert_equal "Reminder: Dentist — tomorrow at 2:00 PM", reminder.message
  end

  test "an exact-time reminder's message is just what the user wrote" do
    reminder = @user.reminders.create!(subject: @user.tasks.create!(title: "Call the pharmacy"), body: "Call the pharmacy", deliver_on: local_today + 1)

    assert_equal "Reminder: Call the pharmacy", reminder.message
  end

  test "a reminder counted back from a task says when it is due, not a made-up time of day" do
    task = @user.tasks.create!(title: "Call the pharmacy", due_on: local_today + 2)
    reminder = @user.reminders.create!(subject: task, lead_minutes: 1440)

    assert_equal "Reminder: Call the pharmacy — due #{(local_today + 2).strftime("%a %b %-d")}", reminder.message
  end

  test "a reminder is always set on something (D-reminders-on-tasks)" do
    reminder = @user.reminders.new(body: "Call the pharmacy", deliver_on: local_today + 1)

    assert_not reminder.valid?
    assert_match(/task or an event/, reminder.errors.full_messages.to_sentence)
  end

  test "a reminder cannot be set in the past, or on someone else's item" do
    assert_not @user.reminders.new(subject: @user.tasks.create!(title: "Too late"), body: "Too late", deliver_on: local_today - 1).valid?

    other_event = users(:two).events.create!(title: "Theirs", starts_date: local_today + 1, starts_time: "09:00")
    assert_not @user.reminders.new(subject: other_event, lead_minutes: 60).valid?
  end

  # --- standing reminders (D-standing-reminders) ---------------------------

  test "a repeat composes an explicit rule from the picked day" do
    thursday = local_today + ((4 - local_today.wday) % 7)
    reminder = @user.reminders.create!(subject: @user.tasks.create!(title: "Take the trash out"), body: "Take the trash out", deliver_on: thursday + 7, deliver_time: "20:00", repeat: "weekly")

    assert_equal "FREQ=WEEKLY;BYDAY=TH", reminder.rule
    assert reminder.standing?
    assert_equal "weekly on Thursday", reminder.cadence
    assert_equal "weekly", reminder.reload.repeat, "the picker reads its key back off the stored rule"
    assert_equal [ "TH" ], reminder.repeat_days
  end

  test "the weekday chips win over the picked date, and the series starts on the first chosen day" do
    saturday = local_today + ((6 - local_today.wday) % 7) + 7
    reminder = @user.reminders.create!(subject: @user.tasks.create!(title: "Take the trash out"), body: "Take the trash out", deliver_on: saturday, deliver_time: "20:00",
      repeat: "weekly", repeat_days: %w[ TH ])

    assert_equal "FREQ=WEEKLY;BYDAY=TH", reminder.rule
    assert_equal 4, reminder.local_deliver_at.wday, "the coming Thursday, not the Saturday that was picked"
    assert_equal 20, reminder.local_deliver_at.hour
    assert reminder.deliver_at > saturday.in_time_zone(@zone)
  end

  test "every option composes, and reads back as itself" do
    date = local_today + 3
    expected = {
      "daily" => "FREQ=DAILY",
      "weekdays" => "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR",
      "biweekly" => "FREQ=WEEKLY;INTERVAL=2;BYDAY=#{Recurrence::Rule::WEEKDAY_CODES[date.wday]}",
      "monthly" => "FREQ=MONTHLY;BYMONTHDAY=#{date.day}",
      "yearly" => "FREQ=YEARLY"
    }

    expected.each do |key, rule|
      reminder = @user.reminders.create!(subject: @user.tasks.create!(title: key), body: key, deliver_on: date, deliver_time: "09:00", repeat: key)
      assert_equal rule, reminder.rule, key
      assert_equal key, Reminder.find(reminder.id).repeat, key
    end
  end

  test "a standing reminder whose first moment has passed rolls forward instead of refusing" do
    reminder = @user.reminders.create!(subject: @user.tasks.create!(title: "Meds"), body: "Meds", deliver_on: local_today - 1, deliver_time: "08:00", repeat: "daily")

    assert reminder.deliver_at > Time.current
    assert reminder.deliver_at <= 1.day.from_now
    assert_equal 8, reminder.local_deliver_at.hour
  end

  test "a one-shot in the past is still refused, on update too" do
    reminder = @user.reminders.create!(subject: @user.tasks.create!(title: "Call the pharmacy"), body: "Call the pharmacy", deliver_on: local_today + 1, deliver_time: "16:00")

    assert_not reminder.update(deliver_on: local_today - 1)
    assert_match(/already passed/, reminder.errors.full_messages.to_sentence)
  end

  test "choosing 'doesn't repeat' clears the rule; a form that never sent a repeat leaves it alone" do
    reminder = @user.reminders.create!(subject: @user.tasks.create!(title: "Meds"), body: "Meds", deliver_on: local_today + 1, deliver_time: "08:00", repeat: "daily")

    reminder = Reminder.find(reminder.id)
    reminder.update!(deliver_time: "09:00")
    assert_equal "FREQ=DAILY", reminder.rule, "an edit that didn't touch Repeat keeps the cadence"

    reminder.update!(repeat: "none")
    assert_nil reminder.rule
    assert_not reminder.standing?
  end

  test "a repeat cannot ride a lead time — there is nothing for it to repeat over" do
    event = create_event(title: "Dentist", starts_date: local_today + 2, starts_time: "14:00")
    reminder = @user.reminders.new(subject: event, lead_minutes: 60, repeat: "weekly")

    assert_not reminder.valid?
    assert_match(/needs its own time/, reminder.errors.full_messages.to_sentence)
  end

  test "a rule the grammar can't stand on is refused" do
    assert_not @user.reminders.new(subject: @user.tasks.create!(title: "Odd"), body: "Odd", deliver_on: local_today + 1, repeat: "FREQ=HOURLY").valid?
    assert_not @user.reminders.new(subject: @user.tasks.create!(title: "Odd"), body: "Odd", deliver_on: local_today + 1, repeat: "fortnightly-ish").valid?
  end

  test "a standing reminder on a task pings like any other and leaves the task alone" do
    task = @user.tasks.create!(title: "Take the trash out")
    reminder = @user.reminders.create!(subject: task, deliver_on: local_today + 1, deliver_time: "20:00", repeat: "weekly")

    assert_equal "Take the trash out", reminder.body
    assert_equal "Reminder: Take the trash out", reminder.message, "the cadence is the card's business, not the ping's"
    assert_nil task.reload.completed_at
  end

  test "a last day rides the rule, reads back, and has to follow the first day" do
    reminder = @user.reminders.create!(subject: @user.tasks.create!(title: "Water the seedlings"), body: "Water the seedlings", deliver_on: local_today + 1, deliver_time: "08:00",
      repeat: "daily", repeat_until: local_today + 30)

    assert_equal "FREQ=DAILY;UNTIL=#{(local_today + 30).strftime('%Y%m%d')}", reminder.rule
    assert_equal local_today + 30, Reminder.find(reminder.id).repeat_until
    assert_match(/until/, reminder.cadence)

    early = @user.reminders.new(subject: @user.tasks.create!(title: "Odd"), body: "Odd", deliver_on: local_today + 5, repeat: "daily", repeat_until: local_today + 1)
    assert_not early.valid?
    assert_match(/before the first/, early.errors.full_messages.to_sentence)

    spent = @user.reminders.new(subject: @user.tasks.create!(title: "Odd"), body: "Odd", deliver_on: local_today - 10, repeat: "daily", repeat_until: local_today - 5)
    assert_not spent.valid?
    assert_match(/already run out/, spent.errors.full_messages.to_sentence)
  end

  test "finishing a task retires its one-shot reminders and keeps its standing ones" do
    task = @user.tasks.create!(title: "Take the trash out", due_on: local_today + 1)
    once = @user.reminders.create!(subject: task, lead_minutes: 60)
    exact = @user.reminders.create!(subject: task, deliver_on: local_today + 1, deliver_time: "07:00")
    weekly = @user.reminders.create!(subject: task, deliver_on: local_today + 1, deliver_time: "20:00", repeat: "weekly")

    task.complete!

    assert_not Reminder.exists?(once.id), "a ping about something already done reads as the app not noticing"
    assert_not Reminder.exists?(exact.id)
    assert Reminder.exists?(weekly.id), "checked off this week is the chore done once, not the chore over"
  end

  test "deleting the item takes its reminders with it" do
    event = create_event(title: "Dentist", starts_date: local_today + 2, starts_time: "14:00")
    @user.reminders.create!(subject: event, lead_minutes: 60)

    assert_difference -> { Reminder.count }, -1 do
      event.destroy!
    end
  end
end
