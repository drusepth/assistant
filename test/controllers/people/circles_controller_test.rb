require "test_helper"

# The circle flag (D-people-dashboard): explicit, manual, and personal — the People page's
# subject is chosen by the user, never inferred from an import.
class People::CirclesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "flags an existing person" do
    person = users(:one).people.create!(name: "Sam")

    post people_circle_path, params: { person_id: person.id }

    assert_redirected_to section_path("people")
    assert person.reload.keep_in_touch?
  end

  test "quick-adds a new person by name, flagged and auto-sorted" do
    assert_enqueued_with(job: CategorizePersonJob) do
      post people_circle_path, params: { name: "  Aunt Rosa  " }
    end

    person = users(:one).people.order(:id).last
    assert_equal "Aunt Rosa", person.name
    assert person.keep_in_touch?
  end

  test "a typed name that's already a contact reuses them rather than duplicating" do
    person = users(:one).people.create!(name: "Aunt Rosa")

    assert_no_difference "Person.count" do
      post people_circle_path, params: { name: "aunt rosa" }
    end
    assert person.reload.keep_in_touch?
  end

  test "prefers the picked person over a typed name" do
    person = users(:one).people.create!(name: "Sam")

    assert_no_difference "Person.count" do
      post people_circle_path, params: { person_id: person.id, name: "Someone else" }
    end
    assert person.reload.keep_in_touch?
  end

  test "with neither a pick nor a name it just asks again" do
    assert_no_difference "Person.count" do
      post people_circle_path, params: { name: "   " }
    end
    assert_redirected_to section_path("people")
  end

  test "unflags without deleting" do
    person = users(:one).people.create!(name: "Sam", keep_in_touch: true)

    delete people_circle_path, params: { person_id: person.id }

    assert_not person.reload.keep_in_touch?
  end

  test "another member's person is not yours to flag" do
    person = users(:two).people.create!(name: "Bob's friend")

    post people_circle_path, params: { person_id: person.id }
    assert_response :not_found
    assert_not person.reload.keep_in_touch?
  end

  # D-person-picker: the picker's own forms are answered in place so the
  # next name can be typed straight away.
  test "an inline add answers with streams: the card, reach out, and a notice with Undo" do
    person = users(:one).people.create!(name: "Sam")

    post people_circle_path, params: { person_id: person.id, inline: "1" }, as: :turbo_stream

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_select "turbo-stream[action=replace][target=circle-summary]"
    assert_select "turbo-stream[action=replace][target=reach-out]"
    assert_select "turbo-stream[action=update][target=flash]" do
      assert_select "template", text: /Sam added to your circle/
    end
    assert_match people_circle_path(person_id: person.id), response.body, "the notice carries its Undo"
    assert_no_match "Add a birthday or phone", response.body, "an existing contact needs no nudge"
  end

  test "a brand-new contact from the picker is offered its next step" do
    post people_circle_path, params: { name: "Cousin Ada", inline: "1" }, as: :turbo_stream

    assert_match "Add a birthday or phone", response.body
    assert_match edit_person_path(Person.find_by(name: "Cousin Ada")), response.body
  end

  test "without the inline flag a Turbo form still gets the redirect, with Undo in the flash" do
    person = users(:one).people.create!(name: "Sam")

    post people_circle_path, params: { person_id: person.id }, as: :turbo_stream

    assert_redirected_to section_path("people")
    assert_equal "delete", flash[:undo]["method"]
  end
end
