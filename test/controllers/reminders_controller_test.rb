require "test_helper"

class RemindersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.household.update!(time_zone: "America/Chicago")
    sign_in_as @user
  end

  test "setting a standalone reminder from Today" do
    post reminders_path, params: {
      reminder: { body: "Call the pharmacy", deliver_on: Date.current + 1, deliver_time: "16:00" }
    }

    reminder = @user.reminders.sole
    assert_equal "Call the pharmacy", reminder.body
    assert_equal 16, reminder.local_deliver_at.hour, "4pm means 4pm where the user lives"
    assert_nil reminder.subject
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

  test "removing a reminder" do
    reminder = @user.reminders.create!(body: "Call the pharmacy", deliver_on: Date.current + 1)

    delete reminder_path(reminder)

    assert_empty @user.reminders.reload
  end

  test "one user cannot delete another's reminder" do
    theirs = users(:two).reminders.create!(body: "Theirs", deliver_on: Date.current + 1)

    delete reminder_path(theirs)

    assert_response :not_found
    assert Reminder.exists?(theirs.id)
  end

  test "Today and the item pages render their reminder controls" do
    event = @user.events.create!(title: "Dentist", starts_date: Date.current + 2, starts_time: "14:00")
    @user.reminders.create!(subject: event, lead_minutes: 60)

    get today_path
    assert_response :success
    assert_select "form[action=?]", reminders_path

    get event_path(event)
    assert_response :success
    assert_select "form[action=?]", reminders_path
  end
end
