require "test_helper"

class AllergiesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "adding an allergy files a Health note with its severity" do
    post allergies_path, params: { allergen: "Penicillin", reaction: "hives and swelling", severity: "severe" }
    assert_redirected_to section_path("health")

    note = users(:one).notes.allergies.sole
    assert_equal "Penicillin", note.title
    assert_equal "hives and swelling", note.body
    assert_equal "severe", note.severity
    assert note.severe?
    assert_equal [ sections(:health) ], note.sections.to_a
  end

  test "reaction and severity are optional, and a blank allergen is refused" do
    post allergies_path, params: { allergen: "Peanuts" }
    note = users(:one).notes.allergies.sole
    assert_equal "Peanuts", note.body, "the allergen stands in for a reaction nobody wrote down"
    assert_nil note.severity

    post allergies_path, params: { allergen: "" }
    assert_equal 1, users(:one).notes.allergies.count
  end

  test "a severity the form never offered is dropped rather than stored" do
    post allergies_path, params: { allergen: "Latex", severity: "catastrophic" }
    assert_nil users(:one).notes.allergies.sole.severity
  end

  test "removing an allergy deletes its note" do
    post allergies_path, params: { allergen: "Bee stings", severity: "moderate" }
    note = users(:one).notes.allergies.sole

    delete allergy_path(note)
    assert_redirected_to section_path("health")
    assert_empty users(:one).notes.allergies
  end

  test "one user cannot remove another's allergy" do
    other = users(:two).notes.create!(kind: Note::ALLERGY, title: "Shellfish", body: "hives")

    delete allergy_path(other)
    assert_response :not_found
    assert other.reload.persisted?
  end

  test "the remove path only reaches allergies, not every note" do
    plain = users(:one).notes.create!(title: "Groceries", body: "milk, eggs")

    delete allergy_path(plain)
    assert_response :not_found
    assert plain.reload.persisted?
  end
end
