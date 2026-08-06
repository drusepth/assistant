require "test_helper"

class SuggestionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @suggestion = users(:one).suggestions.create!(
      watcher_slug: "checkup_cadence", fingerprint: "checkup_cadence/test",
      title: "Book a health checkup",
      action: { "task" => { "title" => "Book a checkup appointment" } }
    )
    @suggestion.sections << sections(:health)
  end

  test "accept materializes the task and marks the suggestion accepted" do
    assert_difference "users(:one).tasks.count" do
      patch accept_suggestion_path(@suggestion)
    end

    assert_redirected_to root_path
    assert @suggestion.reload.accepted?

    task = users(:one).tasks.last
    assert_equal "Book a checkup appointment", task.title
    assert_equal [ sections(:health) ], task.sections.to_a
  end

  test "accept on a tool action redirects to the prefilled run form" do
    suggestion = users(:one).suggestions.create!(
      watcher_slug: "checkup_cadence", fingerprint: "checkup_cadence/tool-test",
      title: "Pick Spanish back up",
      action: { "tool" => { "slug" => "learn_something", "inputs" => { "topic" => "Spanish" } } }
    )

    assert_no_difference "users(:one).tasks.count" do
      patch accept_suggestion_path(suggestion)
    end

    assert_redirected_to new_tool_run_path("learn_something", inputs: { topic: "Spanish" })
    assert suggestion.reload.accepted?
  end

  test "dismiss and snooze update status without creating anything" do
    assert_no_difference "users(:one).tasks.count" do
      patch dismiss_suggestion_path(@suggestion)
    end
    assert @suggestion.reload.dismissed?

    @suggestion.update!(status: :pending)
    patch snooze_suggestion_path(@suggestion)
    assert @suggestion.reload.snoozed?
    assert_equal 2.weeks.from_now.to_date, @suggestion.snoozed_until
  end

  test "only the owner can act on a suggestion" do
    sign_in_as users(:two)

    patch accept_suggestion_path(@suggestion)
    assert_response :not_found
    assert @suggestion.reload.pending?
  end

  test "the dashboard and the section page surface actionable suggestions" do
    get root_path
    assert_match "Book a health checkup", response.body
    assert_match "From your assistant", response.body

    get section_path("health")
    assert_match "Book a health checkup", response.body
    assert_match "Needs your attention", response.body
  end

  test "dismissed suggestions disappear from both surfaces" do
    @suggestion.dismiss!

    get root_path
    assert_no_match "Book a health checkup", response.body

    get section_path("health")
    assert_no_match "Book a health checkup", response.body
  end
end
