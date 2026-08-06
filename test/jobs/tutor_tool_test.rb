require "test_helper"

# The chat kind's proving tool (D22): opening message from owned Education
# context, replies over a windowed transcript, and a recap Note as the only
# primitive — saved on explicit request, and what gives the next session
# its memory.
class TutorToolTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @run = users(:one).tool_runs.create!(
      tool_slug: "tutor",
      inputs: { "topic" => "fractions", "learner" => "my 9-year-old" }
    )
  end

  test "the opening message draws on the Education lens — plans, progress, past recaps" do
    goal = users(:one).goals.create!(title: "Learn fractions", broken_down_at: Time.current)
    goal.sections << sections(:education)
    users(:one).tasks.create!(goal: goal, title: "Practice halves and quarters", completed_at: Time.current)
    recap = users(:one).notes.create!(title: "Tutoring recap — fractions", body: "Struggled with common denominators.")
    recap.sections << sections(:education)

    stub_chat("Hi! Last time common denominators were tricky — want to start there?")

    ToolRunJob.perform_now(@run)

    @run.reload
    assert @run.done?, "done means live for a chat run"

    message = @run.tool_run_messages.sole
    assert message.assistant_role?
    assert_match(/common denominators/, message.content)

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("Learn fractions (1/1 steps done)") &&
        request.body.include?("Struggled with common denominators") &&
        request.body.include?("my 9-year-old")
    end
  end

  test "a turn appends the reply over the transcript" do
    @run.tool_run_messages.create!(role: :assistant, content: "Where shall we start?")
    @run.tool_run_messages.create!(role: :user, content: "What is 1/2 + 1/4?")
    @run.update!(status: :done)
    stub_chat("What do the two bottom numbers tell you?")

    ChatTurnJob.perform_now(@run)

    assert_equal 3, @run.tool_run_messages.count
    assert @run.tool_run_messages.ordered.last.assistant_role?
    assert_not @run.awaiting_reply?

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("What is 1/2 + 1/4?") && request.body.include?("Where shall we start?")
    end
  end

  test "the transcript window drops old turns and notices are never sent to the model" do
    @run.tool_run_messages.create!(role: :user, content: "OLDEST-MARKER")
    33.times { |i| @run.tool_run_messages.create!(role: i.even? ? :assistant : :user, content: "turn #{i}") }
    @run.tool_run_messages.create!(role: :notice, content: "NOTICE-MARKER")
    stub_chat("reply")

    ChatTurnJob.perform_now(@run)

    assert_requested(:post, ENDPOINT) do |request|
      !request.body.include?("OLDEST-MARKER") &&
        !request.body.include?("NOTICE-MARKER") &&
        request.body.include?("turn 32")
    end
  end

  test "a failed turn appends a retry notice instead of poisoning the run" do
    @run.tool_run_messages.create!(role: :user, content: "hello?")
    @run.update!(status: :done)
    stub_request(:post, ENDPOINT).to_return(status: 500, body: "boom")

    ChatTurnJob.perform_now(@run)

    @run.reload
    assert @run.done?, "the run stays live"
    notice = @run.tool_run_messages.ordered.last
    assert notice.notice_role?
    assert_match(/send another/i, notice.content)
    assert_not @run.awaiting_reply?, "the thinking indicator can't stick"
  end

  test "saving a recap lands one Education-filed note on the run" do
    @run.tool_run_messages.create!(role: :assistant, content: "Nice work today.")
    stub_request(:post, ENDPOINT).to_return(
      status: 200,
      body: { choices: [ { message: { content: {
        recap: { title: "Tutoring recap — fractions", body: "Covered halves and quarters; practice thirds next." }
      }.to_json } } ] }.to_json
    )

    ChatRecapJob.perform_now(@run)

    note = @run.reload.items.grep(Note).sole
    assert_equal "Tutoring recap — fractions", note.title
    assert_match(/practice thirds/, note.body)
    assert_equal [ sections(:education) ], note.sections,
      "recaps are filed where the tool lives — future sessions read them back as context"
  end

  private
    def stub_chat(content)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: content } } ] }.to_json
      )
    end
end
