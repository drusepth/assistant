require "test_helper"

class GoalsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @goal = users(:one).goals.create!(title: "Find a new job")
  end

  test "index redirects to the merged Tasks section" do
    get goals_path
    assert_redirected_to tasks_path
  end

  test "creating a goal queues the AI breakdown and lands on the goal's page" do
    assert_enqueued_with(job: BreakDownGoalJob) do
      post goals_path, params: { goal: { title: "Fight the eviction" } }
    end
    # The goal page is the bridge between planning and doing
    # (D-tasks-two-surfaces): the plan streams in right where you land.
    assert_redirected_to goal_path(Goal.last)
  end

  test "hand-tagged goals still get broken down" do
    assert_enqueued_with(job: BreakDownGoalJob) do
      post goals_path, params: { goal: { title: "Fight the eviction", section_ids: [ sections(:rights).id ] } }
    end
    assert_equal [ sections(:rights) ], Goal.last.sections.to_a
  end

  test "no breakdown without a configured model profile" do
    sign_in_as users(:outsider)
    assert_no_enqueued_jobs(only: BreakDownGoalJob) do
      post goals_path, params: { goal: { title: "Get fit" } }
    end
  end

  test "marks a goal done and reactivates it" do
    patch complete_goal_path(@goal)
    assert @goal.reload.done?

    patch reopen_goal_path(@goal)
    assert @goal.reload.active?
  end

  test "pauses and resumes a goal (D-goal-pause)" do
    patch pause_goal_path(@goal)
    assert @goal.reload.paused?

    patch resume_goal_path(@goal)
    assert @goal.reload.active?
  end

  test "cannot pause another user's goal" do
    other = users(:two).goals.create!(title: "Bob's goal")
    patch pause_goal_path(other)
    assert_response :not_found
  end

  test "break_down queues an append run for a planned goal" do
    @goal.tasks.create!(user: users(:one), title: "Existing step")

    assert_enqueued_with(job: BreakDownGoalJob, args: [ @goal, { append: true } ]) do
      post break_down_goal_path(@goal)
    end
    assert_redirected_to goal_path(@goal)
  end

  test "show renders steps without a duplicate goal chip" do
    @goal.tasks.create!(user: users(:one), title: "Update resume")
    get goal_path(@goal)
    assert_response :success
    assert_match "Update resume", response.body
  end

  test "new form is quick capture" do
    get new_goal_path
    assert_response :success
    assert_match "What are you working toward?", response.body
  end

  test "new form takes a title carried over from a quick-add" do
    get new_goal_path(title: "Run a 10k")
    assert_select "input[name=?][value=?]", "goal[title]", "Run a 10k"
  end

  test "cannot act on another user's goal" do
    other = users(:two).goals.create!(title: "Bob's goal")
    patch complete_goal_path(other)
    assert_response :not_found
  end
end
