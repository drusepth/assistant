require "test_helper"

class CheckupCadenceWatcherTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @watcher = Watcher::CheckupCadence.new(@user)
  end

  test "proposes the generic checkup when the health calendar is silent for a year" do
    suggestion = @watcher.scan.sole

    assert suggestion.persisted?
    assert_equal "Book a health checkup", suggestion.title
    assert_equal [ sections(:health) ], suggestion.sections.to_a
    assert_equal "checkup_cadence", suggestion.watcher_slug
    assert_equal({ "task" => { "title" => "Book a checkup appointment" } }, suggestion.action)
  end

  test "stays quiet when a recent health event exists, even an unclassifiable one" do
    health_event "Therapy session", 2.months.ago

    assert_empty @watcher.scan
    assert_empty @user.suggestions
  end

  test "stays quiet when a health event is coming up" do
    health_event "Acupuncture", 3.weeks.from_now

    assert_empty @watcher.scan
    assert_empty @user.suggestions
  end

  test "an overdue kind gets its own nudge whose accept opens find-care prefilled" do
    health_event "Dental cleaning", 8.months.ago
    health_event "Annual physical", 2.months.ago

    suggestion = @watcher.scan.sole
    assert_equal "Book a dental cleaning", suggestion.title
    assert_match(/every 6 months/, suggestion.body)
    assert_equal(
      { "tool" => { "slug" => "find_care", "inputs" => { "specialty" => "dentist" } } },
      suggestion.action
    )
    assert_equal [ sections(:health) ], suggestion.sections.to_a
  end

  test "per-kind history beats the generic nudge even when the last year is silent" do
    health_event "Annual physical", 14.months.ago

    titles = @watcher.scan.map(&:title)
    assert_equal [ "Book a checkup" ], titles, "the specific nudge replaces the generic one"
  end

  test "a booked appointment quiets its kind" do
    health_event "Dental cleaning", 8.months.ago
    health_event "Dentist", 2.weeks.from_now

    assert_empty @watcher.scan
  end

  test "no nudge for a kind with no history — the radar panel handles unknowns" do
    health_event "Annual physical", 2.months.ago

    assert_empty @watcher.scan, "no dental or vision history means no dental or vision nudge"
  end

  test "another user's shared event is not your checkup" do
    event = users(:two).events.create!(title: "Bob's physical", starts_at: 1.month.ago, all_day: true)
    event.sections << sections(:health)
    AccessGrant.create!(grantor: users(:two), grantee: @user, subject: event)

    assert_equal [ "Book a health checkup" ], @watcher.scan.map(&:title)
  end

  test "rescanning never duplicates, and a dismissal keeps it quiet" do
    health_event "Eye exam", 30.months.ago

    first = @watcher.scan.sole
    assert_empty Watcher::CheckupCadence.new(@user).scan
    assert_equal 1, @user.suggestions.count

    first.dismiss!
    assert_empty Watcher::CheckupCadence.new(@user).scan
    assert_equal 1, @user.suggestions.count, "a dismissed nudge must not return this period"
  end

  private
    def health_event(title, starts_at)
      event = @user.events.create!(title: title, starts_at: starts_at, all_day: true)
      event.sections << sections(:health)
      event
    end
end
