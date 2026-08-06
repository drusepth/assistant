require "test_helper"

class EventsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { sign_in_as users(:one) }

  test "creates an event" do
    assert_difference("Event.count") do
      post events_path, params: { event: { title: "Cardiology", starts_at: 3.days.from_now, section_ids: [ sections(:health).id ] } }
    end
    assert_redirected_to calendar_path
  end

  test "new form is quick capture: title, date picker, shortcut chips" do
    get new_event_path(date: "2026-08-10")
    assert_response :success
    assert_match "happening?", response.body
    assert_match "Tomorrow", response.body
    assert_match "2026-08-10", response.body
  end

  test "quick-adding a title and day queues auto-sorting" do
    assert_enqueued_with(job: CategorizeEventJob) do
      post events_path, params: { event: { title: "Dentist at 3pm", starts_at: "2026-08-10", all_day: true } }
    end
    event = Event.last
    assert event.all_day?
    assert_equal Date.new(2026, 8, 10), event.starts_at.to_date
  end

  test "hand-tagged events are not auto-sorted" do
    assert_no_enqueued_jobs(only: CategorizeEventJob) do
      post events_path, params: { event: { title: "Cardiology", starts_at: 3.days.from_now, section_ids: [ sections(:health).id ] } }
    end
  end

  test "rejects an event without required fields" do
    post events_path, params: { event: { title: "" } }
    assert_response :unprocessable_entity
  end

  test "updates own event but not others'" do
    mine = users(:one).events.create!(title: "Mine", starts_at: 1.day.from_now)
    patch event_path(mine), params: { event: { title: "Mine, renamed" } }
    assert_redirected_to event_path(mine)

    other = users(:two).events.create!(title: "Bob's", starts_at: 1.day.from_now)
    patch event_path(other), params: { event: { title: "Hijacked" } }
    assert_response :not_found
  end
end
