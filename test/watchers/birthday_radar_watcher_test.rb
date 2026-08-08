require "test_helper"

# Circle birthdays within three weeks earn a heads-up whose accept lands a
# gift task and the day on the calendar — deterministic, yearly fingerprint,
# and never about the rolodex.
class BirthdayRadarWatcherTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  test "a circle birthday in range earns a heads-up with a task-and-event action" do
    person = circle_person("Sam", birthday_in: 10.days)
    date = person.next_birthday

    suggestion = scan.sole
    assert suggestion.heads_up?
    assert_equal "birthday_radar/person:#{person.id}/#{date.year}", suggestion.fingerprint
    assert_includes suggestion.title, "Sam's birthday"
    assert_equal "Get ready", suggestion.accept_label
    assert_equal (date - 7).iso8601, suggestion.action.dig("task", "due_on")
    assert_equal date.iso8601, suggestion.action.dig("event", "starts_at")
    assert_includes suggestion.sections, sections(:people)
  end

  test "accepting lands both the gift task and the calendar day" do
    person = circle_person("Sam", birthday_in: 10.days)

    suggestion = scan.sole
    created = nil
    assert_difference [ "Task.count", "Event.count" ], 1 do
      created = suggestion.accept!
    end

    assert_equal "Get a birthday gift for Sam", created.title
    event = @user.events.order(:id).last
    assert_equal "Sam's birthday", event.title
    assert event.all_day?
    assert_equal person.next_birthday, event.starts_at.to_date
  end

  test "a birthday under a week away gets a gift task due today, not in the past" do
    circle_person("Sam", birthday_in: 3.days)

    assert_equal Date.current.iso8601, scan.sole.action.dig("task", "due_on")
  end

  test "rolodex, far-off, and birthday-less people stay quiet" do
    @user.people.create!(name: "Acquaintance", birthday: 10.days.from_now.to_date - 30.years)
    circle_person("Far off", birthday_in: 2.months)
    @user.people.create!(name: "No birthday", keep_in_touch: true)

    assert_empty scan
  end

  test "one heads-up per person per year, even across dismissals" do
    circle_person("Sam", birthday_in: 10.days)
    scan.sole.dismiss!

    assert_no_difference "Suggestion.count" do
      Watcher::BirthdayRadar.new(@user).scan
    end
  end

  private
    def scan
      Watcher::BirthdayRadar.new(@user).scan
      @user.suggestions.pending.order(:id).to_a
    end

    def circle_person(name, birthday_in:)
      @user.people.create!(
        name: name, keep_in_touch: true,
        birthday: birthday_in.from_now.to_date - 30.years
      )
    end
end
