require "test_helper"

class NotesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "creates a note" do
    assert_difference("Note.count") do
      post notes_path, params: { note: { title: "Context", body: "Allergic to penicillin.", section_ids: [ sections(:health).id ] } }
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
