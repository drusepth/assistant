require "test_helper"

class TodayControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "shows overdue, due-today, and upcoming items" do
    users(:one).tasks.create!(title: "Very late", due_on: 3.days.ago)
    users(:one).tasks.create!(title: "Do today", due_on: Date.current)
    users(:one).events.create!(title: "Tonight", starts_at: Time.current.end_of_day - 1.hour)

    get today_path
    assert_response :success
    assert_match "Very late", response.body
    assert_match "Do today", response.body
    assert_match "Tonight", response.body
  end

  test "shows tomorrow's tasks and events in the get-ready section" do
    users(:one).tasks.create!(title: "Pack gym bag", due_on: Date.tomorrow)
    users(:one).events.create!(title: "Dentist checkup", starts_at: Date.tomorrow.noon)

    get today_path
    assert_response :success
    assert_match "Get ready for tomorrow", response.body
    assert_match "Pack gym bag", response.body
    assert_match "Dentist checkup", response.body
  end

  test "does not show other users' private items" do
    users(:two).tasks.create!(title: "Bob's secret errand", due_on: Date.current)

    get today_path
    assert_response :success
    assert_no_match "Bob&#39;s secret errand", response.body
  end
end
