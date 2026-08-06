require "test_helper"

class TaskTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @goal = @user.goals.create!(title: "Find a new job")
  end

  test "for_today? is bucket or due date" do
    assert_not @user.tasks.create!(title: "Someday").for_today?
    assert @user.tasks.create!(title: "Picked", bucket: :today).for_today?
    assert @user.tasks.create!(title: "Due", due_on: Date.current).for_today?
    assert @user.tasks.create!(title: "Overdue", due_on: Date.yesterday).for_today?
    assert_not @user.tasks.create!(title: "Due later", due_on: Date.tomorrow).for_today?
  end

  test "completing the last open task finishes the goal" do
    first = @user.tasks.create!(title: "Update resume", goal: @goal)
    second = @user.tasks.create!(title: "Apply", goal: @goal)

    first.complete!
    assert @goal.reload.active?

    second.complete!
    assert @goal.reload.done?
  end

  test "reopening a task reactivates a finished goal" do
    task = @user.tasks.create!(title: "Update resume", goal: @goal)
    task.complete!
    assert @goal.reload.done?

    task.reopen!
    assert @goal.reload.active?
  end
end
