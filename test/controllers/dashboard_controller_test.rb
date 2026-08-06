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
    assert_select "button[data-quick-add-name-param=note]", text: /Note/
    assert_match "Overdue thing", response.body
    assert_match "Checkup", response.body
  end

  test "renders inline quick-add forms for every primitive" do
    sign_in_as users(:one)

    get root_path
    assert_response :success
    assert_select "[data-controller=quick-add]" do
      assert_select "form[action=?]", tasks_path
      assert_select "form[action=?]", notes_path
      assert_select "form[action=?]", events_path
      assert_select "form[action=?]", goals_path
      assert_select "input[name=return_to][value=?]", root_path, count: 4
    end
  end

  test "creating from a quick-add form returns to the dashboard" do
    sign_in_as users(:one)

    post tasks_path, params: { return_to: root_path, task: { title: "From the dashboard" } }
    assert_redirected_to root_path

    post events_path, params: { return_to: root_path, event: { title: "Checkup", starts_date: Date.tomorrow } }
    assert_redirected_to root_path

    post notes_path, params: { return_to: root_path, note: { body: "Remember this" } }
    assert_redirected_to root_path

    post goals_path, params: { return_to: root_path, goal: { title: "Get organized" } }
    assert_redirected_to root_path
  end

  test "ignores a non-local return_to" do
    sign_in_as users(:one)

    post tasks_path, params: { return_to: "https://evil.example", task: { title: "Sneaky" } }
    assert_redirected_to tasks_path

    post tasks_path, params: { return_to: "//evil.example", task: { title: "Sneakier" } }
    assert_redirected_to tasks_path
  end

  test "shows ongoing multi-day events in upcoming" do
    sign_in_as users(:one)
    users(:one).events.create!(title: "Conference week", starts_at: 2.days.ago, ends_at: 2.days.from_now)

    get root_path
    assert_match "Conference week", response.body
  end
end
