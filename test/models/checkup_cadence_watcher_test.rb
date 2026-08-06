require "test_helper"

class CheckupCadenceWatcherTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @watcher = Watcher::CheckupCadence.new(@user)
  end

  test "proposes a checkup when the health calendar is silent for a year" do
    suggestion = @watcher.scan

    assert suggestion.persisted?
    assert_equal "Book a health checkup", suggestion.title
    assert_equal [ sections(:health) ], suggestion.sections.to_a
    assert_equal "checkup_cadence", suggestion.watcher_slug
    assert_equal({ "task" => { "title" => "Book a checkup appointment" } }, suggestion.action)
  end

  test "stays quiet when a recent health event exists" do
    event = @user.events.create!(title: "Physical", starts_at: 2.months.ago, all_day: true)
    event.sections << sections(:health)

    assert_nil @watcher.scan
    assert_empty @user.suggestions
  end

  test "stays quiet when a health event is coming up" do
    event = @user.events.create!(title: "Dentist", starts_at: 3.weeks.from_now, all_day: true)
    event.sections << sections(:health)

    assert_nil @watcher.scan
    assert_empty @user.suggestions
  end

  test "another user's shared event is not your checkup" do
    event = users(:two).events.create!(title: "Bob's physical", starts_at: 1.month.ago, all_day: true)
    event.sections << sections(:health)
    AccessGrant.create!(grantor: users(:two), grantee: @user, subject: event)

    assert @watcher.scan.persisted?
  end

  test "rescanning never duplicates, and a dismissal keeps it quiet" do
    first = @watcher.scan
    assert_nil @watcher.scan
    assert_equal 1, @user.suggestions.count

    first.dismiss!
    assert_nil @watcher.scan
    assert_equal 1, @user.suggestions.count, "a dismissed nudge must not return this period"
  end
end
