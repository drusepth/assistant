require "test_helper"

class CalendarControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "renders the current month with visible events" do
    users(:one).events.create!(title: "Dentist", starts_at: Date.current.noon)
    users(:two).events.create!(title: "Bob private", starts_at: Date.current.noon)

    get calendar_path
    assert_response :success
    assert_match "Dentist", response.body
    assert_no_match "Bob private", response.body
  end

  test "renders a specific month" do
    get calendar_path(year: 2026, month: 1)
    assert_response :success
    assert_select "h1", text: "January 2026"
  end
end
