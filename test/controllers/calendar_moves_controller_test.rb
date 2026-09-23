require "test_helper"

class CalendarMovesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "dragging an event to another day keeps its time and length" do
    event = users(:one).events.create!(title: "Haircut",
      starts_at: Time.zone.local(2026, 9, 22, 15), ends_at: Time.zone.local(2026, 9, 22, 16, 30))

    post calendar_moves_path, params: { kind: "event", id: event.id, date: "2026-09-24" }
    assert_response :no_content
    assert_equal Time.zone.local(2026, 9, 24, 15), event.reload.starts_at
    assert_equal Time.zone.local(2026, 9, 24, 16, 30), event.ends_at
    assert_equal "“Haircut” moved to Thu Sep 24.", flash[:notice]
  end

  test "dragging a task changes its due date" do
    task = users(:one).tasks.create!(title: "Renew passport", due_on: "2026-09-22")

    post calendar_moves_path, params: { kind: "task", id: task.id, date: "2026-09-30" }
    assert_equal Date.new(2026, 9, 30), task.reload.due_on
  end

  test "a relative reminder follows the event it counts back from" do
    event = users(:one).events.create!(title: "Haircut", starts_at: 2.days.from_now.change(hour: 15))
    reminder = users(:one).reminders.create!(subject: event, lead_minutes: 60)

    post calendar_moves_path, params: { kind: "event", id: event.id, date: (Date.current + 5).iso8601 }
    assert_equal event.reload.starts_at - 1.hour, reminder.reload.deliver_at
  end

  test "someone else's items don't move" do
    task = users(:two).tasks.create!(title: "Bob's", due_on: "2026-09-22")

    post calendar_moves_path, params: { kind: "task", id: task.id, date: "2026-09-30" }
    assert_response :not_found
    assert_equal Date.new(2026, 9, 22), task.reload.due_on
  end

  test "a bad date says so" do
    task = users(:one).tasks.create!(title: "Renew passport", due_on: "2026-09-22")

    post calendar_moves_path, params: { kind: "task", id: task.id, date: "someday" }
    assert_response :unprocessable_entity
    assert_equal Date.new(2026, 9, 22), task.reload.due_on
  end
end
