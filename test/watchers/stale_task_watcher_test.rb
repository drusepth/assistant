require "test_helper"

# The forgotten-task rescue: an undated Later-column task is invisible to the
# Dashboard and Today page (both query by due date), so after three weeks it
# earns a nudge whose accept pulls the task itself into Today.
class StaleTaskWatcherTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @task = stale_task("Fix the gutter")
  end

  test "an undated task parked in Later earns one nudge with a schedule action" do
    suggestion = scan.sole

    assert suggestion.pending?
    assert suggestion.nudge?
    assert_equal "stale_task", suggestion.watcher_slug
    assert_equal "stale_task/task:#{@task.id}/#{Date.current.strftime("%Y-%m")}", suggestion.fingerprint
    assert_includes suggestion.title, "Fix the gutter"
    assert_equal({ "schedule_task" => { "id" => @task.id } }, suggestion.action)
    assert_equal "Do it today", suggestion.accept_label
  end

  test "the suggestion files under the task's own sections" do
    @task.sections = [ sections(:health) ]

    assert_equal [ sections(:health) ], scan.sole.sections.to_a
  end

  test "accepting pulls the existing task into Today instead of creating one" do
    suggestion = scan.sole

    assert_no_difference "Task.count" do
      assert_equal @task, suggestion.accept!
    end

    assert suggestion.accepted?
    assert_equal Date.current, @task.reload.due_on
    assert @task.today?
  end

  test "accepting after the task was completed is a quiet no-op" do
    suggestion = scan.sole
    @task.complete!

    assert_nil suggestion.accept!
    assert suggestion.accepted?
  end

  test "young, dated, pulled-in, goal-linked, and completed tasks are left alone" do
    @task.destroy!
    @user.tasks.create!(title: "Fresh idea")
    stale_task("Has a date").update_columns(due_on: 2.weeks.from_now.to_date)
    stale_task("Already in Today").update_columns(bucket: Task.buckets[:today])
    goal = @user.goals.create!(title: "Learn piano")
    stale_task("Goal step").update_columns(goal_id: goal.id)
    stale_task("Already done").update_columns(completed_at: Time.current)

    assert_empty scan
  end

  test "another member's stale task is not this user's business" do
    @task.destroy!
    task = users(:two).tasks.create!(title: "Bob's backlog")
    task.update_columns(created_at: 4.weeks.ago)

    assert_empty scan
  end

  test "at most three live nudges at a time, oldest tasks first" do
    @task.destroy!
    tasks = 5.times.map { |i| stale_task("Backlog #{i}", age: (10 - i).weeks) }

    suggestions = scan
    assert_equal 3, suggestions.count
    assert_equal tasks.first(3).map(&:id),
      suggestions.map { |suggestion| suggestion.action.dig("schedule_task", "id") }

    assert_no_difference "Suggestion.count" do
      Watcher::StaleTask.new(@user).scan
    end
  end

  test "resolving a nudge frees its slot for the next oldest task" do
    @task.destroy!
    5.times { |i| stale_task("Backlog #{i}", age: (10 - i).weeks) }
    scan.first.dismiss!

    assert_difference "Suggestion.count", 1 do
      Watcher::StaleTask.new(@user).scan
    end
    assert_equal 3, @user.suggestions.actionable.count
  end

  private
    def scan
      Watcher::StaleTask.new(@user).scan
      @user.suggestions.pending.order(:id).to_a
    end

    def stale_task(title, age: 4.weeks)
      @user.tasks.create!(title: title).tap { |task| task.update_columns(created_at: age.ago) }
    end
end
