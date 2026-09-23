require "test_helper"

# The task page's conversation (D30) and the full-screen door a phone takes to
# it (D-chat-shell).
class Tasks::ConversationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @task = users(:one).tasks.create!(title: "Decide about the lease")
  end

  test "the task page keeps the panel from sm up and offers a door below it" do
    @task.update!(guiding_questions: [ "What would make staying worth it?" ])
    get task_path(@task)

    assert_response :success
    assert_select "a[href=?].sm\\:hidden", task_conversation_path(@task)
    assert_select ".hidden.sm\\:block .chat-panel"
  end

  test "an errand gets only the door, at every width (D-task-answer-shape)" do
    get task_path(@task)

    assert_select "a[href=?]", task_conversation_path(@task)
    assert_select "a[href=?].sm\\:hidden", task_conversation_path(@task), count: 0
    assert_select ".chat-panel", count: 0
  end

  test "the conversation opens as a screen before a run exists" do
    get task_conversation_path(@task)

    assert_response :success
    assert_select ".chat-page .chat-screen"
    assert_select ".chat-screen .composer"
    # The task's capture-time questions stand in for a transcript, at no
    # model cost — the run is still not created.
    assert_select "#chat-transcript .bubble-assistant"
    assert_nil @task.reload.conversation
  end

  test "an existing conversation renders its transcript and links back to the task" do
    post task_conversation_path(@task), params: { content: "Where do I start?" }

    get task_conversation_path(@task)

    assert_response :success
    assert_match "Where do I start?", response.body
    assert_select ".chat-screen a[aria-label=?]", "Back to the task"
    assert_select ".chat-screen a[href=?]", task_path(@task)
  end

  test "a turn posted from the screen keeps its client token" do
    post task_conversation_path(@task), params: { content: "Drawn already", client_token: "cxyz789" }

    turn = @task.reload.conversation.tool_run_messages.user_role.sole
    assert_equal "cxyz789", turn.client_token
  end

  test "you can't open someone else's conversation" do
    theirs = users(:two).tasks.create!(title: "Not yours")

    get task_conversation_path(theirs)

    assert_response :not_found
  end
end
