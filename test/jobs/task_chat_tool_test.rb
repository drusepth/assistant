require "test_helper"

# The task page's conversation tool (D30): replies carry the task and its
# goal context in the system prompt, and the recap verb saves the
# conversation's answer onto the task instead of filing a Note.
class TaskChatToolTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @goal = users(:one).goals.create!(title: "Start a company", broken_down_at: Time.current)
    @task = users(:one).tasks.create!(
      goal: @goal, title: "Brainstorm potential business ideas",
      notes: "List at least 3-5 ideas.",
      guiding_questions: [ "What skills do you enjoy using most?" ]
    )
    users(:one).tasks.create!(goal: @goal, title: "Register the LLC")
    @run = users(:one).tool_runs.create!(tool_slug: "task_chat", subject: @task, status: :done)
    @run.tool_run_messages.create!(role: :assistant, content: "What skills do you enjoy using most?")
    @run.tool_run_messages.create!(role: :user, content: "Writing and teaching, mostly.")
  end

  test "a reply carries the task, its notes, and its goal's steps in the system prompt" do
    stub_chat("Great — what problems do writers and teachers hit that you could solve?")

    ChatTurnJob.perform_now(@run)

    assert @run.tool_run_messages.ordered.last.assistant_role?
    assert_requested(:post, ENDPOINT) do |request|
      system = JSON.parse(request.body)["messages"].first["content"]
      system.include?("Brainstorm potential business ideas") &&
        system.include?("List at least 3-5 ideas.") &&
        system.include?("Start a company") &&
        system.include?("Register the LLC") &&
        system.include?("← this task")
    end
  end

  test "the recap verb saves the answer onto the task, filing no Note" do
    @run.update_column(:recap_requested_at, Time.current)
    stub_request(:post, ENDPOINT).to_return(
      status: 200,
      body: { choices: [ { message: { content: {
        answer: { body: "1. Tutoring service for adult learners…" }
      }.to_json } } ] }.to_json
    )

    assert_no_difference -> { Note.count } do
      ChatRecapJob.perform_now(@run)
    end

    assert_equal "1. Tutoring service for adult learners…", @task.reload.resolution
    assert @run.tool_run_messages.ordered.last.notice_role?
    assert_nil @run.reload.recap_requested_at
  end

  test "a saved answer is shown to the model on later turns" do
    @task.update!(resolution: "Tutoring for adult learners")
    stub_chat("Want to pressure-test the tutoring idea?")

    ChatTurnJob.perform_now(@run)

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("Tutoring for adult learners")
    end
  end

  test "an empty answer from the model becomes a retryable notice, not a blank save" do
    @task.update!(resolution: "keep me")
    stub_request(:post, ENDPOINT).to_return(
      status: 200,
      body: { choices: [ { message: { content: { answer: { body: "" } }.to_json } } ] }.to_json
    )

    ChatRecapJob.perform_now(@run)

    assert_equal "keep me", @task.reload.resolution
    assert_match(/try again/i, @run.tool_run_messages.ordered.last.content)
  end

  test "deleting the task deletes its conversation" do
    @task.destroy!
    assert_not ToolRun.exists?(@run.id)
  end

  private
    def stub_chat(content)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: content } } ] }.to_json
      )
    end
end
