require "test_helper"

# An interview on the calendar with no prep run behind it earns one offer
# of the prep tool, prefilled with the event's own title.
class InterviewAheadWatcherTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  test "an upcoming interview with no prep run earns the nudge" do
    event = @user.events.create!(title: "Interview — shift lead at Acme", starts_at: 3.days.from_now)

    suggestion = scan.sole
    assert_equal "interview_ahead/event:#{event.id}", suggestion.fingerprint
    assert_includes suggestion.title, "Interview — shift lead at Acme"
    assert_equal({ "tool" => { "slug" => "interview_prep",
                               "inputs" => { "role" => "Interview — shift lead at Acme" } } },
      suggestion.action)
  end

  test "a prep run after the event was booked keeps it quiet" do
    @user.events.create!(title: "Phone interview with Bravo", starts_at: 3.days.from_now)
    @user.tool_runs.create!(tool_slug: "interview_prep", inputs: { "role" => "Bravo" })

    assert_empty scan
  end

  test "past interviews, far-future interviews, and other events stay quiet" do
    @user.events.create!(title: "Interview at Acme", starts_at: 2.days.ago)
    @user.events.create!(title: "Interview at Bravo", starts_at: 3.weeks.from_now)
    @user.events.create!(title: "Dentist", starts_at: 3.days.from_now)

    assert_empty scan
  end

  test "another member's interview is not this user's business" do
    users(:two).events.create!(title: "Interview at Acme", starts_at: 3.days.from_now)

    assert_empty scan
  end

  private
    def scan
      Watcher::InterviewAhead.new(@user).scan
      @user.suggestions.pending.order(:id).to_a
    end
end
