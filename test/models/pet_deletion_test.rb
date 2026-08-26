require "test_helper"

# The three deletion paths a pet touches. Each of these was a real defect
# found by asking "what else deletes this?" before merging.
class PetDeletionTest < ActiveSupport::TestCase
  test "removing a contact who is a pet's vet leaves the pet, not a 500" do
    pet = create_pet
    vet = users(:one).people.create!(name: "Dr Chen", relationship: "Vet")
    pet.update!(vet: vet)

    vet.destroy!

    assert_nil pet.reload.vet_id, "the address book is not a claim about the dog"
    assert Pet.exists?(pet.id)
  end

  test "her lens goes with her by every path, not just the controller's" do
    member = users(:one).household.users.create!(name: "Temp", email_address: "temp@example.com",
      password: "password", onboarded_at: Time.current)
    pet = create_pet(user: member, name: "Orphan")
    lens_id = pet.section_id

    member.destroy!

    assert_not Pet.exists?(pet.id)
    assert_not Section.exists?(lens_id),
      "removing a household member used to leave an empty lens under People forever"
  end

  test "items tagged with her keep their other tags" do
    pet = create_pet
    event = users(:one).events.create!(title: "Vet", starts_at: 1.week.from_now)
    event.sections << [ sections(:health), pet.section ]

    pet.destroy!

    assert_equal [ sections(:health) ], event.reload.sections.to_a
  end
end
