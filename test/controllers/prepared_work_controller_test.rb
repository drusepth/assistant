require "test_helper"

# The click path through a prepared draft (D-agent-prepared-work): Review
# opens it without accepting anything, Save is the D20 click that lands it,
# Discard leaves no trace and takes the nudge with it.
class PreparedWorkControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as @user
    @run = @user.tool_runs.create!(
      tool_slug: "find_care", inputs: { "specialty" => "dentist" },
      origin: :agent, status: :prepared,
      output: { "landings" => [
        { "kind" => "note", "title" => "How to find a dentist", "body" => "Call your insurer…",
          "sections" => [ sections(:health).id ] },
        { "kind" => "task", "title" => "Call member services", "due_on" => nil,
          "sections" => [ sections(:health).id ] }
      ] }
    )
    @suggestion = @user.suggestions.create!(
      watcher_slug: "checkup_cadence", fingerprint: "checkup_cadence/dental",
      title: "Book a dental cleaning", tool_run: @run,
      action: { "tool" => { "slug" => "find_care", "inputs" => { "specialty" => "dentist" } } }
    )
  end

  test "accepting a prepared suggestion opens the review without accepting it" do
    assert_no_difference [ -> { @user.notes.count }, -> { @user.tasks.count } ] do
      patch accept_suggestion_path(@suggestion)
    end

    assert_redirected_to @run
    assert_predicate @suggestion.reload, :pending?, "looking is not accepting"
  end

  test "the review page shows the draft and says nothing is saved" do
    get tool_run_path(@run)

    assert_response :success
    assert_select "body", /How to find a dentist/
    assert_select "body", /Nothing is saved yet/
    assert_select "body", /Prepared by your assistant/
  end

  test "saving lands the work and accepts the suggestion" do
    assert_difference [ -> { @user.notes.count }, -> { @user.tasks.count } ], 1 do
      post land_tool_run_path(@run)
    end

    assert_redirected_to @run
    assert_predicate @run.reload, :done?
    assert_predicate @suggestion.reload, :accepted?
    assert_equal [ sections(:health) ], @user.notes.last.sections.to_a
  end

  test "discarding saves nothing and retires the nudge" do
    assert_no_difference [ -> { @user.notes.count }, -> { @user.tasks.count } ] do
      post discard_tool_run_path(@run)
    end

    assert_predicate @run.reload, :discarded?
    assert_predicate @suggestion.reload, :dismissed?, "having said no once is enough"
  end

  test "saving twice lands the work once" do
    post land_tool_run_path(@run)

    assert_no_difference -> { @user.notes.count } do
      post land_tool_run_path(@run)
    end
  end

  test "another member cannot see or land someone else's prepared draft" do
    sign_in_as users(:two)

    get tool_run_path(@run)
    assert_response :not_found

    assert_no_difference -> { @user.notes.count } do
      post land_tool_run_path(@run)
    end
    assert_response :not_found
  end
end
