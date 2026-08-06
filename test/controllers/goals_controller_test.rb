require "test_helper"

class GoalsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @goal = users(:one).goals.create!(title: "Find a new job")
  end

  test "boards render columns" do
    get goals_path
    assert_response :success
    assert_match "Backlog", response.body
    assert_match "Find a new job", response.body
  end

  test "moves a goal between statuses" do
    patch move_goal_path(@goal, status: "active")
    assert @goal.reload.active?
  end

  test "rejects an unknown status" do
    patch move_goal_path(@goal, status: "bogus")
    assert_response :bad_request
  end

  test "creates a goal" do
    assert_difference("Goal.count") do
      post goals_path, params: { goal: { title: "Fight the eviction", status: "active", section_ids: [ sections(:rights).id ] } }
    end
  end

  test "quick-adding a bare title queues auto-sorting" do
    assert_enqueued_with(job: CategorizeGoalJob) do
      post goals_path, params: { goal: { title: "Save $5k by December" } }
    end
  end

  test "hand-tagged goals are not auto-sorted" do
    assert_no_enqueued_jobs(only: CategorizeGoalJob) do
      post goals_path, params: { goal: { title: "Fight the eviction", section_ids: [ sections(:rights).id ] } }
    end
  end

  test "new form is quick capture" do
    get new_goal_path
    assert_response :success
    assert_match "What are you working toward?", response.body
  end
end
