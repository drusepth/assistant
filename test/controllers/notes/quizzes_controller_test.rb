require "test_helper"

# One click on a note page opens a quiz bound to it (D-note-quiz) — no form,
# because the note is the input.
class Notes::QuizzesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    sign_in_as users(:one)
    @note = users(:one).notes.create!(body: "Feed 1:1:1 by weight.")
  end

  test "starting a quiz binds a run to the note and opens it" do
    assert_enqueued_with(job: ToolRunJob) do
      post note_quizzes_path(@note)
    end

    run = users(:one).tool_runs.sole
    assert_equal "quiz_note", run.tool_slug
    assert_equal @note, run.subject
    assert_redirected_to run
  end

  test "the note page offers the quiz and lists the ones already taken" do
    post note_quizzes_path(@note)

    get note_path(@note)
    assert_response :success
    assert_match "Quiz me again", response.body
    assert_match "Quizzes on this note", response.body
  end

  test "with no model configured the note page doesn't offer a quiz it can't write" do
    households(:smith).model_profile.update_column(:api_key, nil)

    get note_path(@note)
    assert_response :success
    assert_no_match "Quiz me on this", response.body
  end

  test "a note shared with you can be quizzed" do
    theirs = users(:two).notes.create!(body: "Shared study material.")
    theirs.access_grants.create!(grantor: users(:two), grantee: users(:one))

    post note_quizzes_path(theirs)

    assert_equal theirs, users(:one).tool_runs.sole.subject

    # Runs are private to whoever took them, so the owner's page lists none.
    sign_in_as users(:two)
    get note_path(theirs)
    assert_response :success
    assert_no_match "Quizzes on this note", response.body
  end

  test "another member's unshared note has no quiz to start" do
    theirs = users(:two).notes.create!(body: "Private.")

    post note_quizzes_path(theirs)

    assert_response :not_found
    assert_empty users(:one).tool_runs
  end

  test "quizzes go with the note they're about" do
    post note_quizzes_path(@note)
    run = users(:one).tool_runs.sole

    assert_difference("ToolRun.count", -1) { @note.destroy! }
    assert_not ToolRun.exists?(run.id)
  end
end
