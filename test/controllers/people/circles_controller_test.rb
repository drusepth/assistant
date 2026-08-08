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
end
