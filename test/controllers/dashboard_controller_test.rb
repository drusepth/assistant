require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "requires authentication" do
    get root_path
    assert_redirected_to new_session_path
  end

  test "renders for a signed-in user" do
    sign_in_as users(:one)
    users(:one).tasks.create!(title: "Overdue thing", due_on: 2.days.ago)
    users(:one).events.create!(title: "Checkup", starts_at: 2.days.from_now)

    get root_path
    assert_response :success
    assert_select "h1", text: "Dashboard"
    assert_select "a[href=?]", new_note_path, text: /Note/
    assert_match "Overdue thing", response.body
    assert_match "Checkup", response.body
  end

  test "shows ongoing multi-day events in upcoming" do
    sign_in_as users(:one)
    users(:one).events.create!(title: "Conference week", starts_at: 2.days.ago, ends_at: 2.days.from_now)

    get root_path
    assert_match "Conference week", response.body
  end
end
