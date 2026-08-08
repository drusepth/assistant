require "test_helper"

# The mental-health check-in (D31): support, not therapy. The crisis
# notice is code-appended at session start and never reaches the model;
# the boundaries live in the system prompt; past recaps are the
# continuity, tutor-style.
class CheckInToolTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @run = users(:one).tool_runs.create!(tool_slug: "check_in", inputs: { "about" => "work has been a lot" })
  end

  test "a session opens with the code-appended crisis notice, which never reaches the model" do
    stub_chat("Hi. Work has been a lot — want to unpack it, or should I just listen?")

    ToolRunJob.perform_now(@run)

    @run.reload
    assert @run.done?, "done means live for a chat run"

    notice = @run.tool_run_messages.ordered.first
    assert notice.notice_role?
    assert_match(/988/, notice.content)
    assert_match(/not therapy/, notice.content)
    assert @run.tool_run_messages.ordered.last.assistant_role?

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("work has been a lot") &&
        request.body.include?("NOT a therapist") &&
        !request.body.include?("Suicide & Crisis Lifeline")
    end
  end

  test "past check-in recaps carry into the next session's system prompt" do
    earlier = users(:one).tool_runs.create!(tool_slug: "check_in", inputs: {}, status: :done)
    recap = users(:one).notes.create!(title: "Check-in recap — the move", body: "The move stress eased after listing next steps.")
    earlier.tool_run_items.create!(item: recap)
    other_note = users(:one).notes.create!(title: "Unrelated", body: "UNRELATED-MARKER")

    stub_chat("Welcome back. Last time the move was weighing on you — how did it go?")
    ToolRunJob.perform_now(@run)

    assert @run.reload.done?
    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("listing next steps") && !request.body.include?("UNRELATED-MARKER")
    end
  end

  test "saving a recap lands one Health-filed note on the run" do
    @run.tool_run_messages.create!(role: :assistant, content: "Take care of yourself this week.")
    @run.update!(status: :done)
    @run.update_column(:recap_requested_at, Time.current)
    stub_request(:post, ENDPOINT).to_return(
      status: 200,
      body: { choices: [ { message: { content: {
        recap: { title: "Check-in recap — a heavy week", body: "Work stress named; the breathing exercise helped." }
      }.to_json } } ] }.to_json
    )

    ChatRecapJob.perform_now(@run)

    note = @run.reload.items.grep(Note).sole
    assert_equal "Check-in recap — a heavy week", note.title
    assert_equal [ sections(:health) ], note.sections.to_a,
      "recaps file under Health — the next session reads them back"
  end

  private
    def stub_chat(content)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: content } } ] }.to_json
      )
    end
end
