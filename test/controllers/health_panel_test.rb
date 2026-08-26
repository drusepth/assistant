require "test_helper"

# The Health lead panel's Allergies card (D37 convention, docs/HEALTH.md §8).
class HealthPanelTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as @user
  end

  test "the allergies card lists worst first, chips the severity, and takes new ones" do
    allergy "Cats", severity: "mild"
    allergy "Penicillin", severity: "severe"

    get section_path("health")
    assert_response :success
    assert_match "Allergies", response.body
    assert_match allergies_path, response.body
    assert_match "Severe", response.body
    assert response.body.index("Penicillin") < response.body.index("Cats"),
      "the one that can put you in an ambulance leads the list"
  end

  test "an unrated allergy sorts last, not as a mild one" do
    allergy "Cats", severity: "mild"
    allergy "Aspirin"

    get section_path("health")
    assert response.body.index("Cats") < response.body.index("Aspirin"),
      "an unrated allergy is an unanswered question, not a small one"
  end

  test "the card invites before there's anything in it" do
    get section_path("health")
    assert_response :success
    assert_match "Allergies", response.body
    assert_match "Allergic to", response.body
    assert_no_match(%r{/health/allergies/\d+}, response.body, "nothing to remove yet")
  end

  test "another member's allergies stay out of your card" do
    note = users(:two).notes.create!(kind: Note::ALLERGY, title: "Shellfish", body: "hives")
    note.sections << sections(:health)

    get section_path("health")
    assert_no_match(/Shellfish/, response.body)
  end

  private
    def allergy(title, severity: nil)
      @user.notes.create!(kind: Note::ALLERGY, title: title, body: "reaction to #{title}", severity: severity)
        .tap { |note| note.sections << sections(:health) }
    end
end
