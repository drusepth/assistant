require "test_helper"

class EventsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "creates an event" do
    assert_difference("Event.count") do
      post events_path, params: { event: { title: "Cardiology", starts_at: 3.days.from_now, section_ids: [ sections(:health).id ] } }
    end
    assert_redirected_to calendar_path
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
