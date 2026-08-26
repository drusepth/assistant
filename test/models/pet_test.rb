require "test_helper"

class PetTest < ActiveSupport::TestCase
  setup { @rex = create_pet(breed: "Golden retriever", born_on: 4.years.ago.to_date) }

  test "a lens makes every primitive addressable to one pet" do
    rex = @rex
    event = users(:one).events.create!(title: "Rex — annual wellness exam", starts_at: 1.week.from_now)
    event.sections << rex.section
    note = users(:one).notes.create!(body: "Hates the vacuum")
    note.sections << rex.section

    assert_equal [ event ], rex.items(Event, users(:one)).to_a
    assert_equal [ note ], rex.items(Note, users(:one)).to_a
    assert_empty rex.items(Task, users(:one)), "nothing tagged, nothing claimed"
  end

  test "a pet's items read through visible_to, so an unshared item stays invisible" do
    rex = @rex
    event = users(:one).events.create!(title: "Vet", starts_at: 1.week.from_now)
    event.sections << rex.section

    assert_empty rex.items(Event, users(:two)), "no grant, no sight"

    users(:one).granted_access_grants.create!(grantee: users(:two), subject: rex.section)
    assert_equal [ event ], rex.items(Event, users(:two)), "a section grant shares everything filed under her name"
  end

  test "an estimated date of birth is hedged, and a known one is not" do
    rex = @rex
    assert_equal "4 years old", rex.age_phrase

    rex.update!(born_on_estimated: true)
    assert_equal "about 4 years old", rex.age_phrase

    rex.update!(born_on: 5.months.ago.to_date, born_on_estimated: false)
    assert_equal "5 months old", rex.age_phrase

    rex.update!(born_on: nil)
    assert_nil rex.age_phrase
  end

  test "the celebration is a real birthday, else the gotcha day, else nothing" do
    rex = @rex
    assert_equal [ rex.born_on, "Birthday" ], rex.celebration

    rex.update!(born_on_estimated: true, adopted_on: Date.new(2022, 6, 1))
    assert_equal [ Date.new(2022, 6, 1), "Gotcha day" ], rex.celebration,
      "a guessed date of birth is not a birthday to celebrate"

    rex.update!(adopted_on: nil)
    assert_nil rex.celebration
  end

  test "a death or a rehoming leaves the record and only stops the nagging" do
    rex = @rex
    assert rex.active?

    rex.update!(died_on: Date.current)
    assert_not rex.active?
    assert rex.died?
    assert_equal [ rex ], Pet.gone.to_a
    assert_empty Pet.active.to_a
    assert Pet.exists?(rex.id), "nothing is deleted"
  end

  test "species is a closed list, because a kind registry keys off it" do
    pet = users(:one).pets.new(name: "Iggy", species: "dinosaur", section: @rex.section)
    assert_not pet.valid?
    assert_includes pet.errors.full_messages.to_sentence, "Species"
  end
end
