require "test_helper"

class ChatsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "lists the user's conversations with the newest turn as the preview" do
    run = chat_run("check_in")
    run.tool_run_messages.create!(role: :assistant, content: "How's the week been?")
    run.tool_run_messages.create!(role: :user, content: "Rough, honestly.")

    get chats_path

    assert_response :success
    assert_match "You: Rough, honestly.", response.body
    assert_match "2 messages", response.body
  end

  test "a notice is app furniture, not the last thing anybody said" do
    run = chat_run("check_in")
    run.tool_run_messages.create!(role: :user, content: "Still there?")
    run.tool_run_messages.create!(role: :notice, content: "Something went wrong — send another message.")

    get chats_path

    assert_match "You: Still there?", response.body
    assert_no_match "Something went wrong", response.body
  end

  test "ordered by the last turn, not by when the conversation started" do
    old = chat_run("check_in", created_at: 5.days.ago)
    fresh = chat_run("tutor", created_at: 1.hour.ago, inputs: { topic: "Calculus" })

    fresh.tool_run_messages.create!(role: :user, content: "Newer conversation, older turn", created_at: 2.days.ago)
    old.tool_run_messages.create!(role: :user, content: "Older conversation, newest turn")

    get chats_path

    assert_operator response.body.index("Older conversation"), :<,
      response.body.index("Newer conversation")
  end

  test "only chat runs, and only your own" do
    chat_run("check_in").tool_run_messages.create!(role: :user, content: "Mine to see")
    document = users(:one).documents.create!(title: "Hospital bill", extracted_text: "Due: $10")
    users(:one).tool_runs.create!(tool_slug: "dispute_letter", status: :done,
      inputs: { document_id: document.id, intent: "remove the charge" })
    theirs = users(:two).tool_runs.create!(tool_slug: "check_in", inputs: {}, status: :done)
    theirs.tool_run_messages.create!(role: :user, content: "Not yours to see")

    get chats_path

    assert_match "Mine to see", response.body
    assert_no_match "Not yours to see", response.body
    assert_no_match "Draft a dispute letter", response.body
  end

  test "a task conversation points at the task, not at the run" do
    task = users(:one).tasks.create!(title: "Decide about the lease")
    run = chat_run("task_chat", subject: task)
    run.tool_run_messages.create!(role: :user, content: "Where do I start?")

    get chats_path

    assert_select "a[href=?]", task_path(task)
    assert_select "a[href=?]", tool_run_path(run), count: 0
    assert_match "Decide about the lease", response.body
  end

  test "filtering by tool narrows the list and ignores a bogus slug" do
    chat_run("check_in").tool_run_messages.create!(role: :user, content: "A check-in turn")
    chat_run("tutor", inputs: { topic: "Calculus" }).tool_run_messages.create!(role: :user, content: "A tutor turn")

    get chats_path(tool: "tutor")
    assert_match "A tutor turn", response.body
    assert_no_match "A check-in turn", response.body

    get chats_path(tool: "dispute_letter")
    assert_match "A tutor turn", response.body
    assert_match "A check-in turn", response.body
  end

  test "a conversation whose opening reply hasn't landed still lists" do
    chat_run("check_in")

    get chats_path

    assert_response :success
    assert_match "Starting…", response.body
  end

  test "empty until there is something to list" do
    get chats_path

    assert_response :success
    assert_match "No conversations yet", response.body
  end

  test "signed out, it's the sign-in page" do
    delete session_path
    get chats_path

    assert_redirected_to new_session_path
  end

  private
    def chat_run(slug, inputs: {}, **attributes)
      users(:one).tool_runs.create!(tool_slug: slug, inputs: inputs, status: :done, **attributes)
    end
end
