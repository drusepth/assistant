require "test_helper"

class SuggestionTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "fingerprints are unique per user, not globally" do
    @user.suggestions.create!(watcher_slug: "checkup_cadence", fingerprint: "checkup_cadence/2026h2", title: "Book a checkup")

    duplicate = @user.suggestions.new(watcher_slug: "checkup_cadence", fingerprint: "checkup_cadence/2026h2", title: "Again")
    assert_not duplicate.valid?

    other = users(:two).suggestions.new(watcher_slug: "checkup_cadence", fingerprint: "checkup_cadence/2026h2", title: "Book a checkup")
    assert other.valid?
  end

  test "actionable covers pending and expired snoozes, nothing else" do
    pending = create_suggestion("a")
    snoozed_ripe = create_suggestion("b")
    snoozed_ripe.update!(status: :snoozed, snoozed_until: Date.current)
    snoozed_waiting = create_suggestion("c")
    snoozed_waiting.update!(status: :snoozed, snoozed_until: Date.tomorrow)
    dismissed = create_suggestion("d")
    dismissed.dismiss!
    accepted = create_suggestion("e")
    accepted.accept!

    assert_equal [ pending, snoozed_ripe ].sort_by(&:id), @user.suggestions.actionable.sort_by(&:id)
  end

  test "accepting a task action creates a Today task tagged with the suggestion's sections" do
    suggestion = create_suggestion("f", action: { "task" => { "title" => "Book a checkup appointment" } })
    suggestion.sections << sections(:health)

    task = suggestion.accept!

    assert suggestion.accepted?
    assert_equal "Book a checkup appointment", task.title
    assert task.today?, "accepted work belongs on today's board, not a backlog"
    assert_equal [ sections(:health) ], task.sections.to_a
  end

  test "snoozing stamps a return date two weeks out" do
    suggestion = create_suggestion("g")
    suggestion.snooze!

    assert suggestion.snoozed?
    assert_equal 2.weeks.from_now.to_date, suggestion.snoozed_until
  end

  test "accept labels follow the action payload" do
    assert_equal "Add task", create_suggestion("h", action: { "task" => { "title" => "x" } }).accept_label
    assert_equal "Open tool", create_suggestion("i", action: { "tool" => { "slug" => "learn_something" } }).accept_label
    assert_equal "Accept", create_suggestion("j").accept_label
  end

  private
    def create_suggestion(fingerprint, action: {})
      @user.suggestions.create!(
        watcher_slug: "checkup_cadence", fingerprint: fingerprint,
        title: "Suggestion #{fingerprint}", action: action
      )
    end
end
