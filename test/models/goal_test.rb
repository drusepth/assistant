require "test_helper"

class GoalTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @goal = @user.goals.create!(title: "Find a new job", broken_down_at: Time.current)
  end

  test "pauses and resumes without ceremony" do
    @goal.pause!
    assert @goal.reload.paused?

    @goal.resume!
    assert @goal.reload.active?
  end

  test "pause only shelves an active goal and resume only wakes a paused one" do
    @goal.update!(status: :done)
    @goal.pause!
    assert @goal.reload.done?

    @goal.resume!
    assert @goal.reload.done?, "resume is paused-to-active, not a reopen"
  end

  test "shape accepts the closed set and nothing else" do
    assert @goal.update(shape: "finite")
    assert @goal.update(shape: "ongoing")
    assert_not @goal.update(shape: "aspirational")
    assert @goal.reload.update(shape: nil)
  end

  test "stale after six quiet weeks, revived by a completed step" do
    assert_not @goal.stale?, "a fresh goal is not stale"

    @goal.update_columns(created_at: 8.weeks.ago, broken_down_at: 8.weeks.ago)
    assert @goal.reload.stale?

    @goal.tasks.create!(user: @user, title: "Update resume", completed_at: 2.days.ago)
    assert_not @goal.reload.stale?
  end

  test "a paused goal is never stale" do
    @goal.update_columns(created_at: 8.weeks.ago, broken_down_at: 8.weeks.ago)
    @goal.reload.pause!
    assert_not @goal.stale?
  end

  test "adrift when no open step will ever surface itself" do
    @goal.tasks.create!(user: @user, title: "Undated backlog thing")
    assert @goal.reload.adrift?, "an undated later-bucket task never resurfaces"

    @goal.tasks.create!(user: @user, title: "Dated thing", due_on: Date.tomorrow)
    assert_not @goal.reload.adrift?
  end

  test "a step pulled into today also counts as a next step" do
    @goal.tasks.create!(user: @user, title: "Pulled in", bucket: :today)
    assert_not @goal.reload.adrift?
  end

  test "momentum counts steps and remembers the last one" do
    assert_equal 0, @goal.steps_this_week
    assert_nil @goal.last_progress_at

    @goal.tasks.create!(user: @user, title: "Old step", completed_at: 3.weeks.ago)
    @goal.tasks.create!(user: @user, title: "Fresh step", completed_at: 1.day.ago)

    @goal.reload
    assert_equal 1, @goal.steps_this_week
    assert_in_delta 1.day.ago.to_f, @goal.last_progress_at.to_f, 5
  end

  test "the strip sorts by attention: today's work, then flagged, then the rest" do
    healthy = @user.goals.create!(title: "Healthy", broken_down_at: Time.current)
    healthy.tasks.create!(user: @user, title: "Soon", due_on: Date.tomorrow)

    working = @user.goals.create!(title: "Working on now", broken_down_at: Time.current)
    working.tasks.create!(user: @user, title: "Do it", due_on: Date.current)

    stale = @user.goals.create!(title: "Gone quiet", broken_down_at: 8.weeks.ago)
    stale.update_columns(created_at: 8.weeks.ago)
    stale.tasks.create!(user: @user, title: "Someday", due_on: 8.weeks.from_now.to_date)

    ordered = Goal.by_attention([ healthy, working, stale.reload ])
    assert_equal [ "Working on now", "Gone quiet", "Healthy" ], ordered.map(&:title)
  end
end
