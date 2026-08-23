require "test_helper"

class Tasks::CelebrationTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    # A second open task for today keeps the board from being clear, so the
    # ordinary tiers can be tested without tripping the biggest one.
    @user.tasks.create!(title: "Still open", bucket: :today)
  end

  test "an ordinary finish is a task-tier party naming the task" do
    task = @user.tasks.create!(title: "Take out the bins", completed_at: Time.current)

    payload = Tasks::Celebration.for(task)

    assert_equal "task", payload[:tier]
    assert_equal "Take out the bins", payload[:note]
    assert payload[:headline].present?
    assert payload[:token].present?
  end

  test "no party for an open task, or for a user who turned celebrations off" do
    open_task = @user.tasks.create!(title: "Not done")
    assert_nil Tasks::Celebration.for(open_task)

    @user.update!(celebrations: false)
    done = @user.tasks.create!(title: "Done", completed_at: Time.current)
    assert_nil Tasks::Celebration.for(done)
  end

  test "a streak count the copy knows about escalates the tier" do
    2.times { |i| @user.tasks.create!(title: "Earlier #{i}", completed_at: Time.current) }
    task = @user.tasks.create!(title: "Third", completed_at: Time.current)

    payload = Tasks::Celebration.for(task)

    assert_equal "streak", payload[:tier]
    assert_equal Tasks::Celebration::STREAK_COPY[3], payload[:headline]
  end

  test "yesterday's finishes don't count toward today's streak" do
    2.times { |i| @user.tasks.create!(title: "Yesterday #{i}", completed_at: 1.day.ago) }
    task = @user.tasks.create!(title: "First today", completed_at: Time.current)

    assert_equal "task", Tasks::Celebration.for(task)[:tier]
  end

  test "the last step of a goal celebrates the goal" do
    goal = @user.goals.create!(title: "Find a new job")
    task = @user.tasks.create!(title: "Send the application", goal: goal)
    task.complete!

    payload = Tasks::Celebration.for(task)

    assert_equal "goal", payload[:tier]
    assert_equal "Find a new job", payload[:note]
  end

  test "clearing everything today outranks a finished goal" do
    @user.tasks.update_all(completed_at: Time.current)
    goal = @user.goals.create!(title: "Find a new job")
    task = @user.tasks.create!(title: "Last one standing", goal: goal, bucket: :today)
    task.complete!

    assert_equal "board", Tasks::Celebration.for(task)[:tier]
  end

  test "a task parked in Later doesn't hold up a cleared day" do
    @user.tasks.update_all(completed_at: Time.current, bucket: Task.buckets[:later])
    @user.tasks.create!(title: "Someday", bucket: :later)
    task = @user.tasks.create!(title: "Today's last", bucket: :today)
    task.complete!

    # The milestone is finishing today's work, not emptying the whole board —
    # a Later pile you deliberately parked shouldn't cost you the fireworks.
    assert_equal "board", Tasks::Celebration.for(task)[:tier]
  end

  test "a due date that has arrived counts as today's work, open or not" do
    @user.tasks.update_all(completed_at: Time.current)
    @user.tasks.create!(title: "Due now", bucket: :later, due_on: Date.current)
    task = @user.tasks.create!(title: "Today's last", bucket: :today)
    task.complete!

    assert_equal "task", Tasks::Celebration.for(task)[:tier]
  end
end
