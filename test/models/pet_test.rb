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

  test "species takes whatever the owner types, and a known one becomes the slug the registries read" do
    iggy = users(:one).pets.new(name: "Iggy", species: "  guinea   pig ", section: @rex.section)
    assert iggy.valid?
    assert_equal "guinea pig", iggy.species
    assert_equal "Guinea pig", iggy.species_label

    [ "Cat", "cats", "CAT", "cat" ].each do |typed|
      pet = users(:one).pets.new(name: "Luna", species: typed, section: @rex.section)
      pet.validate
      assert_equal "cat", pet.species, "#{typed.inspect} is the cat the vaccine catalog knows"
    end

    assert_equal "Other", users(:one).pets.new(species: "other").species_label, "pets saved before stay readable"
  end

  test "species is still required, and a typed one gets the generic slate rather than an invented one" do
    pet = users(:one).pets.new(name: "Iggy", species: " ", section: @rex.section)
    assert_not pet.valid?
    assert_includes pet.errors.full_messages.to_sentence, "Species"

    pet.species = "Axolotl"
    assert_equal [ "pet_wellness" ], Pets::CareKinds.for(pet).map(&:key)
    assert_empty Pets::Vaccines.for(pet.species)
  end

  test "sex is a closed list, because the app's copy reads it for a pronoun" do
    pet = users(:one).pets.new(name: "Iggy", species: "other", sex: "tomcat", section: @rex.section)
    assert_not pet.valid?
    assert_includes pet.errors.full_messages.to_sentence, "Sex"

    pet.sex = ""
    pet.validate
    assert_empty pet.errors[:sex], "an unrecorded sex is a real answer, not an invalid one"
  end

  test "pronouns follow the recorded sex, and an unrecorded one is they" do
    rex = @rex
    assert_equal "they", rex.pronouns.subject, "nothing recorded, so nothing assumed"
    assert_equal "their", rex.pronouns.possessive
    assert rex.pronouns.plural?
    assert_equal "eat", rex.pronouns.verb("eats", "eat")
    assert_equal "they're", rex.pronouns.is

    rex.update!(sex: "male")
    assert_equal %w[ he him his himself ],
      [ rex.pronouns.subject, rex.pronouns.object, rex.pronouns.possessive, rex.pronouns.reflexive ]
    assert_not rex.pronouns.plural?
    assert_equal "eats", rex.pronouns.verb("eats", "eat")
    assert_equal "he's", rex.pronouns.is

    rex.update!(sex: "female")
    assert_equal %w[ she her her herself ],
      [ rex.pronouns.subject, rex.pronouns.object, rex.pronouns.possessive, rex.pronouns.reflexive ]
  end

  test "the sex label carries the spay or neuter, which is a status and not a sex" do
    rex = @rex
    assert_nil rex.sex_label, "nothing recorded, nothing printed"

    rex.update!(sex: "male")
    assert_equal "Male", rex.sex_label

    rex.update!(neutered: true)
    assert_equal "Neutered male", rex.sex_label
    assert_equal "he", rex.pronouns.subject, "neutering does not change the pronoun"

    rex.update!(sex: "female")
    assert_equal "Spayed female", rex.sex_label
  end
end
