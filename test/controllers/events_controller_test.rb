require "test_helper"

class EventsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { sign_in_as users(:one) }

  test "creates a timed event from date and time parts" do
    assert_difference("Event.count") do
      post events_path, params: { event: {
        title: "Cardiology", starts_date: "2026-08-20", starts_time: "14:00", section_ids: [ sections(:health).id ]
      } }
    end
    assert_redirected_to calendar_path
    event = Event.last
    assert_not event.all_day?
    assert_equal Time.zone.local(2026, 8, 20, 14, 0), event.starts_at
  end

  test "new form is quick capture: title, date picker, shortcut chips" do
    get new_event_path(date: "2026-08-10")
    assert_response :success
    assert_match "happening?", response.body
    assert_match "Tomorrow", response.body
    assert_match "2026-08-10", response.body
  end

  test "new form accepts a prefilled title, care-radar style" do
    get new_event_path(title: "Dental cleaning", section_ids: [ sections(:health).id ])
    assert_response :success
    assert_match "Dental cleaning", response.body
  end

  test "a health event's page offers the counts-as override and saves it" do
    event = users(:one).events.create!(title: "Dr. Chen, 2pm", starts_at: 1.month.ago, all_day: true)
    event.sections << sections(:health)

    get event_path(event)
    assert_response :success
    assert_match "Counts as", response.body

    patch event_path(event), params: { event: { care_kind: "checkup" } }
    assert_equal "checkup", event.reload.care_kind
  end

  test "quick-adding a title and day queues auto-sorting" do
    assert_enqueued_with(job: CategorizeEventJob) do
      post events_path, params: { event: { title: "Dentist at 3pm", starts_date: "2026-08-10" } }
    end
    event = Event.last
    assert event.all_day?
    assert_equal Date.new(2026, 8, 10), event.starts_at.to_date
  end

  test "quick-add takes an optional location" do
    get new_event_path
    assert_match "Where (optional)", response.body

    post events_path, params: { event: { title: "Vet checkup", starts_date: "2026-08-10", location: "Oak Street Animal Clinic" } }
    assert_equal "Oak Street Animal Clinic", Event.last.location
  end

  test "hand-tagged events are not auto-sorted" do
    assert_no_enqueued_jobs(only: CategorizeEventJob) do
      post events_path, params: { event: { title: "Cardiology", starts_date: "2026-08-20", section_ids: [ sections(:health).id ] } }
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
