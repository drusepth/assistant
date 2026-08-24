require "test_helper"

# Paging backwards through a windowed transcript (CHAT_PLAN.md W3). The
# composer's own POST is covered in tool_runs_controller_test.
class ToolRunMessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @run = users(:one).tool_runs.create!(tool_slug: "tutor", inputs: { topic: "Calculus" }, status: :done)
  end

  test "the transcript opens on the newest page, with a seam offering the rest" do
    say(ToolRunMessage::PAGE + 5)

    get tool_run_path(@run)

    assert_response :success
    assert_no_match "turn 1 ", response.body
    assert_match "turn #{ToolRunMessage::PAGE + 5} ", response.body
    assert_select "#chat-earlier a", "Earlier messages"
  end

  test "a short conversation renders whole, with the seam hidden" do
    say(3)

    get tool_run_path(@run)

    assert_match "turn 1 ", response.body
    assert_select "#chat-earlier a", count: 0
    assert_select "#chat-earlier.hidden"
  end

  test "loading earlier turns streams the batch and the next seam" do
    page = ToolRunMessage::PAGE
    say(page * 2 + 5) # 85 turns: the page opens on 46-85, so this batch is 6-45
    oldest_shown = @run.tool_run_messages.newest_first.limit(page).last

    get tool_run_messages_path(@run, before: oldest_shown.id), as: :turbo_stream

    assert_response :success
    assert_match %(action="after" target="chat-earlier"), response.body
    assert_match %(action="replace" target="chat-earlier"), response.body

    body = response.body
    assert_includes body, "turn #{page + 5} of"          # the oldest already on screen...
    assert_not_includes body, "turn #{page + 6} of"      # ...and nothing newer than it
    assert_includes body, "turn 6 of"                    # a full page back
    assert_not_includes body, "turn 5 of"                # which still leaves history
    assert_match "Earlier messages", body
  end

  test "reaching the start of the conversation retires the seam" do
    say(ToolRunMessage::PAGE + 2)
    oldest_shown = @run.tool_run_messages.newest_first.limit(ToolRunMessage::PAGE).last

    get tool_run_messages_path(@run, before: oldest_shown.id), as: :turbo_stream

    assert_match "turn 1 ", response.body
    assert_no_match "Earlier messages", response.body
  end

  test "paging respects the transcript's own order, not just the id column" do
    late = @run.tool_run_messages.create!(role: :user, content: "written first, dated last",
      created_at: 1.hour.from_now)
    early = @run.tool_run_messages.create!(role: :assistant, content: "written second, dated first",
      created_at: 1.hour.ago)

    assert_operator early.id, :>, late.id
    assert_equal [ early, late ], @run.tool_run_messages.ordered.to_a
    assert_equal [ early ], @run.tool_run_messages.before(late).to_a
  end

  test "without JavaScript, the seam link is just the run page" do
    say(2)

    get tool_run_messages_path(@run, before: @run.tool_run_messages.first.id)

    assert_redirected_to tool_run_path(@run)
  end

  test "a cursor that isn't this run's message is refused" do
    say(2)
    elsewhere = users(:one).tool_runs.create!(tool_slug: "check_in", inputs: {}, status: :done)
      .tool_run_messages.create!(role: :user, content: "another conversation")

    get tool_run_messages_path(@run, before: elsewhere.id), as: :turbo_stream
    assert_response :bad_request

    get tool_run_messages_path(@run, before: "nonsense"), as: :turbo_stream
    assert_response :bad_request
  end

  test "you can't page through someone else's transcript" do
    say(2)
    cursor = @run.tool_run_messages.last
    sign_in_as users(:two)

    get tool_run_messages_path(@run, before: cursor.id), as: :turbo_stream

    assert_response :not_found
  end

  test "a draft-kind run has no transcript to page" do
    document = users(:one).documents.create!(title: "Bill", extracted_text: "Due: $10")
    draft = users(:one).tool_runs.create!(tool_slug: "dispute_letter", status: :done,
      inputs: { document_id: document.id, intent: "remove the charge" })

    get tool_run_messages_path(draft, before: 1), as: :turbo_stream

    assert_response :unprocessable_entity
  end

  private
    # Alternating speakers so nothing groups away, numbered so a test can name
    # exactly which turns rendered.
    def say(count)
      count.times do |index|
        @run.tool_run_messages.create!(
          role: index.even? ? :user : :assistant,
          content: "turn #{index + 1} of the conversation",
          created_at: count.minutes.ago + index.minutes
        )
      end
    end
end
