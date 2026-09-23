require "test_helper"

# D-pet-vaccinations W3: a vaccine certificate read by intake.
class Landing::PetVaccinationKindTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @rex = create_pet(user: @user)
    @document = @user.documents.create!(title: "Rabies certificate")
    @context = Landing::Context.new(user: @user, document: @document)
    @landing = Landing::PetVaccination.new(@context)
  end

  def proposed(**attrs)
    { "pet" => @rex.section.slug, "vaccine" => "rabies", "name" => "Nobivac 3-Rabies",
      "given_on" => "2026-06-03", "due_on" => "2029-06-03", "tag_number" => "R-2291" }.merge(attrs.transform_keys(&:to_s))
  end

  test "a dose lands on her record with the certificate linked" do
    dose = @landing.land!(@landing.validate(proposed), sections: [])

    assert_equal @rex, dose.pet
    assert_equal "rabies", dose.vaccine_key
    assert_equal "Nobivac 3-Rabies", dose.name
    assert_equal Date.new(2029, 6, 3), dose.due_on
    assert_equal "R-2291", dose.tag_number
    assert_equal @document, dose.document
  end

  test "the vaccine is a closed set, and one that doesn't fit her species lands as free text" do
    assert_nil @landing.validate(proposed(vaccine: "hepatitis_z"))&.dig("vaccine")

    dose = @landing.land!(@landing.validate(proposed(vaccine: "fvrcp", name: "Purevax RCP")), sections: [])
    assert_nil dose.vaccine_key, "a dog has no FVRCP; the printed name stands instead"
    assert_equal "Purevax RCP", dose.name
  end

  test "reactions and notes are never proposed" do
    assert_nil Landing::PetVaccination.field_named(:reaction)
    assert_nil Landing::PetVaccination.field_named(:notes)
  end

  test "the same dose twice is flagged as a duplicate" do
    @landing.land!(@landing.validate(proposed), sections: [])
    assert @landing.duplicate_of(proposed)
    assert_nil @landing.duplicate_of(proposed(given_on: "2025-06-03"))
  end

  test "the prompt line lists the catalog and the pet refs" do
    line = Landing::PetVaccination.prompt_line(@context)
    assert_match "pet_vaccination", line
    assert_match "rabies", line
    assert_match "other", line
  end
end
