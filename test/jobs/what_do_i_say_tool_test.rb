require "test_helper"

# The second chat tool (D29): hard-conversation coaching that opens knowing
# the situation and the person, and files its recap under People plus the
# person's own sections.
class WhatDoISayToolTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @person = users(:one).people.create!(
      name: "Dad", relationship: "father", notes: "Proud; hates being fussed over"
    )
    @run = users(:one).tool_runs.create!(
      tool_slug: "what_do_i_say",
      inputs: { "situation" => "Set a boundary", "person_id" => @person.id.to_s,
                "details" => "He keeps commenting on my parenting" }
    )
  end

  test "the opening knows the situation and the person" do
    stub_chat("That's a hard one with a proud parent. Here's a first draft…")

    ToolRunJob.perform_now(@run)

    assert @run.reload.done?, "done means live for a chat run"
    assert @run.tool_run_messages.sole.assistant_role?

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("Set a boundary") &&
        request.body.include?("hates being fussed over") &&
        request.body.include?("commenting on my parenting")
    end
  end

  test "works without a person — the situation and details carry it" do
    run = users(:one).tool_runs.create!(
      tool_slug: "what_do_i_say", inputs: { "situation" => "Say no to something" }
    )
    stub_chat("What are you saying no to?")

    ToolRunJob.perform_now(run)

    assert run.reload.done?
  end

  test "the recap files under People plus the person's sections" do
    @person.sections << sections(:health)
    @run.tool_run_messages.create!(role: :assistant, content: "Draft…")
    @run.tool_run_messages.create!(role: :user, content: "That works.")
    @run.update!(status: :done)

    stub_request(:post, ENDPOINT).to_return(
      status: 200,
      body: { choices: [ { message: { content: {
        recap: { title: "What to say — setting a boundary with Dad", body: "Dad, I love you, and…" }
      }.to_json } } ] }.to_json
    )

    ChatRecapJob.perform_now(@run)

    note = @run.reload.items.grep(Note).sole
    assert_equal "What to say — setting a boundary with Dad", note.title
    assert_equal [ sections(:people), sections(:health) ].sort_by(&:id), note.sections.sort_by(&:id)
  end

  private
    def stub_chat(content)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: content } } ] }.to_json
      )
    end
end
