require "test_helper"

class SuggestionTest < ActiveSupport::TestCase
  setup do
    @lens = Hobbies::Lens.find_or_create!("Guitar")
    @suggestion = users(:one).suggestions.create!(
      watcher_slug: "neglected_hobby", fingerprint: "neglected_hobby:#{@lens.id}",
      title: "It's been a while since anything Guitar",
      action: {
        "type" => "create_event", "title" => "Guitar session",
        "on" => Date.tomorrow.iso8601, "section_ids" => [ sections(:hobbies).id, @lens.id ]
      }
    )
  end

  test "accept performs the payload: an all-day event, tagged, and the status flips" do
    event = @suggestion.accept!

    assert @suggestion.accepted?
    assert_equal "Guitar session", event.title
    assert event.all_day?
    assert_equal Date.tomorrow, event.starts_at.to_date
    assert_equal users(:one), event.user
    assert_includes event.sections, sections(:hobbies)
    assert_includes event.sections, @lens
  end

  test "accept survives a lens deleted between scan and click" do
    @lens.destroy!

    event = @suggestion.reload.accept!
    assert_equal [ sections(:hobbies) ], event.sections.to_a
  end

  test "expired snoozes wake back to pending; unexpired ones stay put" do
    @suggestion.snooze!(1.week.from_now)
    users(:one).suggestions.wake_expired_snoozes!
    assert @suggestion.reload.snoozed?

    @suggestion.update!(snoozed_until: 1.minute.ago)
    users(:one).suggestions.wake_expired_snoozes!
    assert @suggestion.reload.pending?
    assert_nil @suggestion.snoozed_until
  end
end
