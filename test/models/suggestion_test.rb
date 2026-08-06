require "test_helper"

# D20: the agent proposes; the user disposes. Accepting is the only path
# from a suggestion to user data, and the payload is re-validated at
# execution time.
class SuggestionTest < ActiveSupport::TestCase
  test "fingerprints are unique per user, not globally" do
    users(:one).suggestions.create!(watcher_slug: "checkup_cadence", fingerprint: "checkup_cadence:2026", title: "t")

    duplicate = users(:one).suggestions.new(watcher_slug: "checkup_cadence", fingerprint: "checkup_cadence:2026", title: "t")
    assert_not duplicate.valid?

    assert users(:two).suggestions.new(watcher_slug: "checkup_cadence", fingerprint: "checkup_cadence:2026", title: "t").valid?
  end

  test "attention covers pending plus snoozes that came back around" do
    pending = make_suggestion("a")
    due_back = make_suggestion("b").tap { |s| s.update!(status: :snoozed, snoozed_until: Date.current) }
    make_suggestion("c").tap { |s| s.update!(status: :snoozed, snoozed_until: Date.tomorrow) }
    make_suggestion("d").tap(&:dismiss!)

    assert_equal [ pending, due_back ].map(&:id).sort, users(:one).suggestions.attention.ids.sort
  end

  test "accepting a create_event payload lands a section-tagged all-day event" do
    suggestion = make_suggestion("e", action: {
      "type" => "create_event", "event" => { "title" => "Book a checkup", "date" => "2026-08-20" }
    })
    suggestion.sections << sections(:health)

    assert_difference -> { users(:one).events.count } do
      suggestion.accept!
    end

    event = users(:one).events.order(:id).last
    assert_equal "Book a checkup", event.title
    assert event.all_day?
    assert_equal Date.new(2026, 8, 20), event.starts_at.to_date
    assert_equal [ sections(:health) ], event.sections
    assert suggestion.accepted?
  end

  test "an unknown action type accepts quietly without touching data" do
    suggestion = make_suggestion("f", action: { "type" => "drop_table" })

    assert_no_difference -> { users(:one).events.count + users(:one).tasks.count } do
      suggestion.accept!
    end
    assert suggestion.accepted?
    assert_nil suggestion.action_type
    assert_equal "Got it", suggestion.accept_label
  end

  test "routed_tool resolves only registered slugs" do
    live = make_suggestion("g", action: { "type" => "run_tool", "slug" => "reconnect" })
    retired = make_suggestion("h", action: { "type" => "run_tool", "slug" => "tool_we_deleted" })

    assert_equal Tool::Reconnect, live.routed_tool
    assert_nil retired.routed_tool
  end

  private
    def make_suggestion(fingerprint, action: {})
      users(:one).suggestions.create!(
        watcher_slug: "checkup_cadence", fingerprint: "test:#{fingerprint}",
        title: "Suggestion #{fingerprint}", action: action
      )
    end
end
