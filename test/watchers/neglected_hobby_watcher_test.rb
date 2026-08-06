require "test_helper"

# The flagship Hobbies watcher: pure SQL, one gentle nudge per quiet lens,
# fingerprint-deduped (with a monthly bucket) so it never nags twice.
class NeglectedHobbyWatcherTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @lens = aged_lens("Guitar")
  end

  test "a quiet lens earns one nudge with a calendar action on a free day" do
    suggestion = scan.sole

    assert suggestion.pending?
    assert suggestion.nudge?
    assert_equal "neglected_hobby", suggestion.watcher_slug
    assert_equal "neglected_hobby/lens:#{@lens.id}/#{Date.current.strftime("%Y-%m")}", suggestion.fingerprint
    assert_includes suggestion.title, "Guitar"
    assert_includes suggestion.sections, sections(:hobbies)
    assert_includes suggestion.sections, @lens
    assert_equal "Add event", suggestion.accept_label

    event = suggestion.action["event"]
    assert_equal "Guitar session", event["title"]
    assert_equal Date.tomorrow.iso8601, event["starts_at"], "tomorrow is free, so tomorrow"
    assert event["all_day"]
  end

  test "accepting materializes the session as an all-day event tagged with the lens" do
    event = scan.sole.accept!

    assert_equal "Guitar session", event.title
    assert event.all_day?
    assert_equal Date.tomorrow, event.starts_at.to_date
    assert_includes event.sections, @lens
    assert_includes event.sections, sections(:hobbies)
  end

  test "the suggested day skips days that already have events" do
    @user.events.create!(title: "Busy", starts_at: Date.tomorrow.in_time_zone.change(hour: 10))

    assert_equal (Date.tomorrow + 1).iso8601, scan.sole.action.dig("event", "starts_at")
  end

  test "a lens younger than the window is left alone" do
    Hobbies::Lens.find_or_create!("Chess")

    assert_equal 1, scan.count, "only the aged lens fires"
  end

  test "recent activity quiets the watcher" do
    task = @user.tasks.create!(title: "Practice scales")
    task.sections = [ @lens ]

    assert_empty scan
  end

  test "an old task checked off recently counts as activity" do
    task = @user.tasks.create!(title: "Practice scales", completed_at: 2.days.ago)
    task.update_columns(created_at: 8.weeks.ago)
    task.sections = [ @lens ]

    assert_empty scan
  end

  test "an upcoming session quiets the watcher" do
    event = @user.events.create!(title: "Jam night", starts_at: 3.days.from_now)
    event.update_columns(created_at: 8.weeks.ago)
    event.sections = [ @lens ]

    assert_empty scan
  end

  test "another member's activity is not this user's activity" do
    task = users(:two).tasks.create!(title: "Bob practices")
    task.sections = [ @lens ]

    assert_equal 1, scan.count
  end

  test "one nudge per lens per month, whatever the user did with it" do
    scan
    assert_no_difference "Suggestion.count" do
      scan
    end

    @user.suggestions.sole.dismiss!
    assert_no_difference "Suggestion.count" do
      scan
    end

    travel 32.days do
      assert_difference "Suggestion.count", 1 do
        Watcher::NeglectedHobby.new(@user).scan
      end
    end
  end

  private
    def scan
      Watcher::NeglectedHobby.new(@user).scan
      @user.suggestions.pending.to_a
    end

    def aged_lens(name)
      Hobbies::Lens.find_or_create!(name).tap { |lens| lens.update_columns(created_at: 8.weeks.ago) }
    end
end
