require "test_helper"

# The Career chat (docs/CAREER.md §3.1): the interviewer persona opens the
# session from owned context — prep sheets and the win log ride along so the
# coaching can name the user's own stories.
class MockInterviewToolTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @run = users(:one).tool_runs.create!(
      tool_slug: "mock_interview",
      inputs: { "focus" => "Warehouse shift lead at Acme", "persona" => "a skeptical operations manager" }
    )
  end

  test "the opening message draws on prep sheets and the win log" do
    prep = users(:one).notes.create!(title: "Interview prep — shift lead",
      body: "Their asks, your answers: inventory experience.")
    prep.sections << sections(:career)
    Career::WinLog.log!(user: users(:one), text: "Caught the inventory error before the audit")

    stub_chat("I'm the operations manager here. Tell me why you want this job.")

    ToolRunJob.perform_now(@run)

    assert @run.reload.done?, "done means live for a chat run"
    assert @run.tool_run_messages.sole.assistant_role?

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("skeptical operations manager") &&
        request.body.include?("Interview prep — shift lead") &&
        request.body.include?("Caught the inventory error")
    end
  end

  test "saving a recap lands one Career-filed note on the run" do
    @run.tool_run_messages.create!(role: :assistant, content: "Good session.")
    @run.update_column(:recap_requested_at, Time.current)
    stub_request(:post, ENDPOINT).to_return(
      status: 200,
      body: { choices: [ { message: { content: {
        recap: { title: "Mock interview recap — shift lead", body: "Tighten the conflict story; lead with the audit win." }
      }.to_json } } ] }.to_json
    )

    ChatRecapJob.perform_now(@run)

    note = @run.reload.items.grep(Note).sole
    assert_equal "Mock interview recap — shift lead", note.title
    assert_equal [ sections(:career) ], note.sections.to_a
  end

  private
    def stub_chat(content)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: content } } ] }.to_json
      )
    end
end
