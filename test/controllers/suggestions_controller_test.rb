require "test_helper"

class SuggestionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @lens = Hobbies::Lens.find_or_create!("Guitar")
    @suggestion = users(:one).suggestions.create!(
      watcher_slug: "neglected_hobby", fingerprint: "neglected_hobby:#{@lens.id}",
      title: "It's been a while since anything Guitar",
      action: {
        "type" => "create_event", "title" => "Guitar session",
        "on" => Date.tomorrow.iso8601, "section_ids" => [ @lens.id ]
      }
    )
  end

  test "accept creates the event and can't be double-clicked" do
    assert_difference "users(:one).events.count", 1 do
      post accept_suggestion_path(@suggestion)
    end
    assert_redirected_to root_path
    assert @suggestion.reload.accepted?

    post accept_suggestion_path(@suggestion)
    assert_response :not_found, "only pending suggestions can be acted on"
  end

  test "dismiss and snooze update the status" do
    post dismiss_suggestion_path(@suggestion)
    assert @suggestion.reload.dismissed?

    @suggestion.update!(status: :pending)
    post snooze_suggestion_path(@suggestion)
    assert @suggestion.reload.snoozed?
    assert_operator @suggestion.snoozed_until, :>, 6.days.from_now
  end

  test "another member's suggestions are untouchable" do
    sign_in_as users(:two)

    post accept_suggestion_path(@suggestion)
    assert_response :not_found
    assert @suggestion.reload.pending?
  end
end
