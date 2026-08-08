require "test_helper"

# The task page's embedded chat (D30): the first message lazily creates the
# bound run seeded with the task's stored openers — no model call until the
# reply job runs — and later messages reuse the same run.
class Tasks::ConversationsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @task = users(:one).tasks.create!(
      title: "Brainstorm potential business ideas",
      guiding_questions: [ "What skills do you enjoy using most?", "Who would you most like to help?" ]
    )
    sign_in_as users(:one)
  end

  test "the first message creates the run seeded with the stored openers, no model call" do
    assert_difference -> { ToolRun.count } => 1, -> { ToolRunMessage.count } => 3 do
      post task_conversation_path(@task), params: { content: "Mostly writing and teaching." }
    end
    assert_redirected_to @task

    run = @task.conversation
    assert_equal "task_chat", run.tool_slug
    assert run.done?, "done means live — the composer stays open"
    assert_equal @task, run.subject

    roles = run.tool_run_messages.ordered.map(&:role)
    assert_equal %w[ assistant assistant user ], roles
    assert_equal "What skills do you enjoy using most?", run.tool_run_messages.ordered.first.content
    assert run.awaiting_reply?
    assert_enqueued_with(job: ChatTurnJob, args: [ run ])
    assert_no_enqueued_jobs only: ToolRunJob
  end

  test "later messages land on the same run" do
    post task_conversation_path(@task), params: { content: "first" }
    run = @task.conversation

    assert_no_difference -> { ToolRun.count } do
      post task_conversation_path(@task), params: { content: "second" }
    end
    assert_equal run, @task.reload.conversation
    assert_equal "second", run.tool_run_messages.ordered.last.content
  end

  test "a blank message creates nothing" do
    assert_no_difference -> { ToolRun.count }, -> { ToolRunMessage.count } do
      post task_conversation_path(@task), params: { content: "" }
    end
    assert_redirected_to @task
  end

  test "only the task's owner can talk on it, even when the task is shared" do
    AccessGrant.create!(grantor: users(:one), grantee: users(:two), subject: @task)
    sign_in_as users(:two)

    post task_conversation_path(@task), params: { content: "hello" }
    assert_response :not_found
  end
end
