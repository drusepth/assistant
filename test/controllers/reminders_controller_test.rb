require "test_helper"

class RemindersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.household.update!(time_zone: "America/Chicago")
    sign_in_as @user
  end

  test "a reminder on nothing is refused — that is a task with a time (D-reminders-on-tasks)" do
    post reminders_path, params: {
      reminder: { body: "Call the pharmacy", deliver_on: Date.current + 1, deliver_time: "16:00" }
    }

    assert_empty @user.reminders
    assert_match(/task or an event/, flash[:alert])
  end

  test "setting a relative reminder on an event" do
    event = @user.events.create!(title: "Dentist", starts_date: Date.current + 2, starts_time: "14:00")

    post reminders_path, params: {
      reminder: { subject_type: "Event", subject_id: event.id, lead_minutes: 60 }
    }

    reminder = @user.reminders.sole
    assert_equal event, reminder.subject
    assert_equal 60, reminder.lead_minutes
    assert_equal "Dentist", reminder.body
  end

  test "a blank lead time falls back to the exact-time fields rather than being ignored" do
    task = @user.tasks.create!(title: "File the appeal", due_on: Date.current + 5)

    post reminders_path, params: {
      reminder: { subject_type: "Task", subject_id: task.id, lead_minutes: "",
                  deliver_on: Date.current + 1, deliver_time: "08:30" }
    }

    reminder = @user.reminders.sole
    assert_nil reminder.lead_minutes
    assert_equal 8, reminder.local_deliver_at.hour
    assert_equal 30, reminder.local_deliver_at.min
  end

  test "a reminder on someone else's item is refused" do
    theirs = users(:two).events.create!(title: "Theirs", starts_date: Date.current + 1, starts_time: "09:00")

    post reminders_path, params: {
      reminder: { subject_type: "Event", subject_id: theirs.id, lead_minutes: 60 }
    }

    assert_empty @user.reminders
    assert_match(/isn't yours/, flash[:alert])
  end

  test "an unknown subject type is refused" do
    post reminders_path, params: {
      reminder: { subject_type: "Credential", subject_id: 1, deliver_on: Date.current + 1 }
    }

    assert_empty @user.reminders
  end

  test "changing a reminder in place" do
    reminder = @user.reminders.create!(subject: @user.tasks.create!(title: "Call the pharmacy"), body: "Call the pharmacy", deliver_on: Date.current + 1, deliver_time: "16:00")

    patch reminder_path(reminder), params: {
      reminder: { body: "Call the pharmacy", deliver_on: Date.current + 1, deliver_time: "10:00", repeat: "weekdays" }
    }

    reminder.reload
    assert_equal 10, reminder.local_deliver_at.hour
    assert_equal "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR", reminder.rule
    assert_match(/every weekday/, flash[:notice])
  end

  test "one user cannot change another's reminder" do
    theirs = users(:two).reminders.create!(subject: users(:two).tasks.create!(title: "Theirs"), body: "Theirs", deliver_on: Date.current + 1)

    patch reminder_path(theirs), params: { reminder: { repeat: "daily" } }

    assert_response :not_found
    assert_nil theirs.reload.rule
  end

  test "removing a reminder" do
    reminder = @user.reminders.create!(subject: @user.tasks.create!(title: "Call the pharmacy"), body: "Call the pharmacy", deliver_on: Date.current + 1)

    delete reminder_path(reminder)

    assert_empty @user.reminders.reload
  end

  test "one user cannot delete another's reminder" do
    theirs = users(:two).reminders.create!(subject: users(:two).tasks.create!(title: "Theirs"), body: "Theirs", deliver_on: Date.current + 1)

    delete reminder_path(theirs)

    assert_response :not_found
    assert Reminder.exists?(theirs.id)
  end

  test "an event page sets reminders without a repeat; Today has no reminder form of its own" do
    event = @user.events.create!(title: "Dentist", starts_date: Date.current + 2, starts_time: "14:00")
    @user.reminders.create!(subject: event, lead_minutes: 60)

    get event_path(event)
    assert_response :success
    assert_select "form[action=?]", reminders_path
    assert_select "li", text: /An hour before/
    assert_select "form[action=?] select[name='reminder[repeat]']", reminders_path, false

    get today_path
    assert_select "form[action=?]", reminders_path, false
  end

  test "a repeating reminder that already exists opens on what was chosen, to change or end it" do
    event = @user.events.create!(title: "Book club", starts_date: Date.current + 2, starts_time: "19:00")
    standing = @user.reminders.create!(subject: event, body: "Book club", deliver_on: Date.current, deliver_time: "20:00",
      repeat: "weekly", repeat_days: [ "TH" ])

    get event_path(event)
    assert_select "li", text: /Weekly on Thursday/
    assert_select "form[action=?] select[name='reminder[repeat]'] option[selected][value=weekly]", reminder_path(standing)
    assert_select "form[action=?] input[name='reminder[repeat_days][]'][value=TH][checked]", reminder_path(standing)
  end
end
