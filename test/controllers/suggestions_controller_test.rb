require "test_helper"

class SuggestionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @suggestion = users(:one).suggestions.create!(
      watcher_slug: "checkup_cadence", fingerprint: "checkup_cadence:2026",
      title: "You might be due for a checkup",
      action: { "type" => "create_event", "event" => { "title" => "Book a checkup", "date" => "2026-08-20" } }
    )
    @suggestion.sections << sections(:health)
  end

  test "accept materializes the payload and reports where it landed" do
    assert_difference -> { users(:one).events.count } do
      post accept_suggestion_path(@suggestion)
    end

    assert_redirected_to root_path
    assert_equal "Added to your calendar.", flash[:notice]
    assert @suggestion.reload.accepted?
  end

  test "accepting a run_tool suggestion hands off to the prefilled form" do
    person = users(:one).people.create!(name: "Rosa")
    suggestion = users(:one).suggestions.create!(
      watcher_slug: "checkup_cadence", fingerprint: "stay_in_touch:#{person.id}",
      title: "It's been a while since you talked to Rosa",
      action: { "type" => "run_tool", "slug" => "reconnect", "inputs" => { "person_id" => person.id.to_s } }
    )

    post accept_suggestion_path(suggestion)

    assert_redirected_to new_tool_run_path("reconnect", inputs: { person_id: person.id.to_s })
    assert suggestion.reload.accepted?
  end

  test "snooze and dismiss quiet the suggestion" do
    post snooze_suggestion_path(@suggestion)
    assert @suggestion.reload.snoozed?
    assert_equal Date.current + 7, @suggestion.snoozed_until

    post dismiss_suggestion_path(@suggestion)
    assert @suggestion.reload.dismissed?
  end

  test "only the owner can act on a suggestion" do
    sign_in_as users(:two)
    post accept_suggestion_path(@suggestion)
    assert_response :not_found
  end

  test "the dashboard and the section's Attend zone surface the suggestion" do
    get root_path
    assert_match "You might be due for a checkup", response.body
    assert_select "form[action=?]", accept_suggestion_path(@suggestion)

    get section_path("health")
    assert_match "You might be due for a checkup", response.body

    get section_path("career")
    assert_no_match(/due for a checkup/, response.body)
  end

  test "accepted suggestions leave the surfaces" do
    @suggestion.accept!

    get root_path
    assert_no_match(/due for a checkup/, response.body)
  end
end
