require "test_helper"

# "Save as note" — the explicit door from an ask-your-email answer into
# the primitive pool (D-mirror-layer).
class SaveAnswerTest < ActionDispatch::IntegrationTest
  setup do
    @run = users(:one).tool_runs.create!(
      tool_slug: "ask_your_email", status: "done",
      inputs: { "question" => "When is the inspection?" },
      output: { "answer" => {
        "question" => "When is the inspection?", "body" => "Friday at 9am.",
        "citations" => [ { "from" => "Sam Landlord", "date" => "2026-08-05" } ],
        "searched" => "your mirrored mail" } })
  end

  test "one click files the answer as a Note with its sources" do
    sign_in_as users(:one)

    assert_difference("Note.count") { post save_answer_tool_run_path(@run) }
    post save_answer_tool_run_path(@run)
    assert_equal 1, @run.reload.items.grep(Note).size, "double-click files one note"

    note = @run.items.grep(Note).sole
    assert_includes note.title, "When is the inspection?"
    assert_includes note.body, "Friday at 9am."
    assert_includes note.body, "Sam Landlord"
  end

  test "another user's run is unreachable" do
    sign_in_as users(:two)

    post save_answer_tool_run_path(@run)
    assert_response :not_found
  end
end
