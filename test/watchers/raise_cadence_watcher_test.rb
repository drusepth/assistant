require "test_helper"

# The section's flagship nudge: the comp timeline quiet for a year earns a
# raise-case offer; no timeline at all earns one lifetime invitation to
# start it — no signal, no nudge (Q8 discipline).
class RaiseCadenceWatcherTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  test "a comp timeline quiet for over a year earns the raise-case nudge" do
    travel_to Date.new(2026, 8, 8) do
      Career::CompChange.log!(user: @user, summary: "Raise: $19 → $21/hr", on: Date.new(2025, 2, 1))

      suggestion = scan.sole
      assert_equal "raise_cadence/2026", suggestion.fingerprint
      assert_includes suggestion.title, "18 months"
      assert_equal({ "tool" => { "slug" => "raise_case" } }, suggestion.action)
      assert_equal [ sections(:career) ], suggestion.sections.to_a
    end
  end

  test "a recent comp change keeps it quiet" do
    Career::CompChange.log!(user: @user, summary: "Raise", on: 6.months.ago.to_date)

    assert_empty scan
  end

  test "no timeline but career activity earns the one-time invitation" do
    note = @user.notes.create!(title: "About my work", body: "Shift lead at Acme.")
    note.sections << sections(:career)

    suggestion = scan.sole
    assert_equal "raise_cadence/invite", suggestion.fingerprint
    assert_match(/watch your raise cadence/, suggestion.title)
    assert suggestion.action.key?("task")
  end

  test "the invitation never repeats once dismissed" do
    note = @user.notes.create!(title: "About my work", body: "Shift lead.")
    note.sections << sections(:career)
    scan.sole.dismiss!

    assert_no_difference "Suggestion.count" do
      Watcher::RaiseCadence.new(@user).scan
    end
  end

  test "no career signal at all stays silent" do
    assert_empty scan
  end

  private
    def scan
      Watcher::RaiseCadence.new(@user).scan
      @user.suggestions.pending.order(:id).to_a
    end
end
