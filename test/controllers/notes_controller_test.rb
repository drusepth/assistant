require "test_helper"

class NotesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { sign_in_as users(:one) }

  test "creates a note" do
    assert_difference("Note.count") do
      post notes_path, params: { note: { title: "Context", body: "Allergic to penicillin.", section_ids: [ sections(:health).id ] } }
    end
  end

  test "new form is quick capture: body only" do
    get new_note_path
    assert_response :success
    assert_match "What should your assistant remember?", response.body
  end

  test "new form takes a body carried over from a quick-add" do
    get new_note_path(body: "Allergic to penicillin")
    assert_select "textarea[name=?]", "note[body]", text: "Allergic to penicillin"
  end

  test "quick-jotting a bare body queues auto-sorting" do
    assert_enqueued_with(job: CategorizeNoteJob) do
      post notes_path, params: { note: { body: "Allergic to penicillin." } }
    end
  end

  test "hand-tagged notes are not auto-sorted" do
    assert_no_enqueued_jobs(only: CategorizeNoteJob) do
      post notes_path, params: { note: { body: "Tagged by hand.", section_ids: [ sections(:health).id ] } }
    end
  end

  test "rejects a bodyless note" do
    post notes_path, params: { note: { title: "Empty" } }
    assert_response :unprocessable_entity
  end

  test "updates own note" do
    note = users(:one).notes.create!(body: "Original")
    patch note_path(note), params: { note: { body: "Updated" } }
    assert_equal "Updated", note.reload.body
  end
end
