require "test_helper"

# The stall, rust, and pace watchers (docs/EDUCATION_PLAN.md §7): SQL
# signals, honest bodies, monthly buckets.
class EducationWatchersTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "a quiet subject earns a re-entry card naming the exact resume point" do
    subjects(:physics).update_column(:updated_at, 3.weeks.ago)

    Watcher::SubjectStall.new(@user).scan

    suggestion = @user.suggestions.sole
    assert_match(/Physics of motion.*gone quiet/, suggestion.title)
    assert_match(/Momentum in an ollie/, suggestion.body)
    assert_equal "/subjects/#{subjects(:physics).id}", suggestion.path_action
  end

  test "a recent study_log keeps the stall card away even when the row is untouched" do
    subjects(:physics).update_column(:updated_at, 3.weeks.ago)
    @user.study_logs.create!(subject: subjects(:physics), on: 2.days.ago.to_date, minutes: 20, activity: :tutor)

    Watcher::SubjectStall.new(@user).scan
    assert_empty @user.suggestions
  end

  test "rusty topics earn one kind card pointing at the queue" do
    topics(:friction).decay!
    Watcher::RustyRadar.new(@user).scan

    suggestion = @user.suggestions.sole
    assert_equal "A mastered topic has gone rusty", suggestion.title
    assert_match(/Friction & grip/, suggestion.body)
    assert_equal "/reviews", suggestion.path_action
  end

  test "pace only speaks when a target exists and the learner is behind — and names every honest exit" do
    Watcher::PaceCheck.new(@user).scan
    assert_empty @user.suggestions, "no target, no pace pressure"

    subject = subjects(:algebra)
    subject.update!(target_date: 10.days.from_now.to_date)
    subject.update_column(:created_at, 100.days.ago)

    Watcher::PaceCheck.new(@user).scan
    suggestion = @user.suggestions.sole
    assert suggestion.heads_up?
    assert_match(/behind its target/, suggestion.title)
    assert_match(/move the date/, suggestion.body)
  end
end
