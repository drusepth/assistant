require "test_helper"

# The health and pet kinds (INTAKE_PLAN W3): what a vet's discharge sheet
# produces, each row where its own page expects it.
class Landing::HealthKindsTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @rex = create_pet(user: @user, weight_kg: 31.2)
    @context = Landing::Context.new(user: @user)
    @health = sections(:health)
  end

  test "a past visit with a care kind lands as Health + the pet's lens, and the pet's radar counts it" do
    landing = Landing::Event.new(@context)
    attrs = landing.validate("title" => "Rex — vaccinations", "on" => 2.weeks.ago.to_date.iso8601,
      "care_kind" => "pet_vaccinations", "pet" => @rex.section.slug)

    event = landing.land!(attrs, sections: [])
    assert_equal "pet_vaccinations", event.care_kind
    assert_equal [ @rex.section, @health ].to_set, event.sections.to_set

    status = Health::CareRadar.new(@rex).statuses.find { |s| s.kind.key == "pet_vaccinations" }
    assert_equal :ok, status.state
    assert_equal event, status.last_visit
  end

  test "a stated due date lands as 'none' so the radar never reads it as booked" do
    landing = Landing::Event.new(@context)
    attrs = landing.validate("title" => "Rex — rabies booster due", "on" => 1.year.from_now.to_date.iso8601,
      "care_kind" => "none", "pet" => @rex.section.slug)
    event = landing.land!(attrs, sections: [])

    assert_equal "none", event.care_kind
    assert_equal [ @rex.section ], event.sections.to_a, "not a visit, so not Health by the care rule"
    status = Health::CareRadar.new(@rex).statuses.find { |s| s.kind.key == "pet_vaccinations" }
    assert_equal :unknown, status.state
  end

  test "care kinds come from the closed set: the user's, each pet's, and none" do
    keys = @context.care_kind_options.map(&:last)
    assert_includes keys, "dental"
    assert_includes keys, "pet_vaccinations"
    assert_includes keys, "none"
    assert_nil Landing::Event.new(@context).validate("title" => "x", "on" => "2026-01-01", "care_kind" => "brain_scan")&.dig("care_kind")
  end

  test "medication: a note of kind medication, Health + the pet, with the refill on the calendar and off the radar" do
    landing = Landing::Medication.new(@context)
    attrs = landing.validate("name" => "Carprofen", "dose_and_schedule" => "75 mg twice a day",
      "refill_on" => "2026-09-12", "pet" => @rex.section.slug)

    note = landing.land!(attrs, sections: [])
    assert note.medication?
    assert_equal "75 mg twice a day", note.body
    assert_equal [ @health, @rex.section ].to_set, note.sections.to_set

    refill = @user.events.find_by!(title: "Refill Carprofen")
    assert_equal "none", refill.care_kind
    assert_equal Date.new(2026, 9, 12), refill.starts_at.to_date
    assert_equal note, landing.duplicate_of("name" => "carprofen")
  end

  test "allergy: severity only from the closed set, never guessed" do
    landing = Landing::Allergy.new(@context)
    attrs = landing.validate("allergen" => "Chicken", "reaction" => "itchy skin", "severity" => "catastrophic", "pet" => @rex.section.slug)
    assert_nil attrs["severity"], "an unknown severity is dropped, not mapped"

    note = landing.land!(attrs, sections: [])
    assert note.allergy?
    assert_nil note.severity
    assert_equal [ @health, @rex.section ].to_set, note.sections.to_set

    rated = landing.land!(landing.validate("allergen" => "Penicillin", "severity" => "severe"), sections: [])
    assert rated.severe?
  end

  test "pet_facts amends the pet's record and previews old → new" do
    vet = @user.people.create!(name: "Dr. Alvarez", relationship: "Vet")
    landing = Landing::PetFacts.new(@context)
    attrs = landing.validate("pet" => @rex.section.slug, "weight_kg" => "32.6 kg", "microchip" => "985112003456789", "vet" => vet.id.to_s)

    assert_equal "32.6", attrs["weight_kg"]
    assert_equal [ [ "Weight", "31.2 kg", "32.6 kg" ], [ "Microchip", nil, "985112003456789" ], [ "Vet", nil, "Dr. Alvarez" ] ],
      landing.amendments(attrs)
    assert_includes landing.preview(attrs).detail, "Weight: 31.2 kg → 32.6 kg"

    assert_no_difference "Pet.count" do
      assert_equal @rex, landing.land!(attrs, sections: [])
    end
    @rex.reload
    assert_equal 32.6, @rex.weight_kg.to_f
    assert_equal "985112003456789", @rex.microchip
    assert_equal vet, @rex.vet
    assert_empty landing.amendments(attrs), "once applied, nothing differs"
  end

  test "pet_facts never touches another member's pet" do
    luna = create_pet(user: users(:two), name: "Luna")
    landing = Landing::PetFacts.new(@context)
    assert_nil landing.validate("pet" => luna.section.slug, "weight_kg" => "4"), "not in the closed set, so the entry sinks"
  end

  test "pet_food lands on the shelf with the bag's numbers, and a current food of the same name is a duplicate" do
    landing = Landing::PetFood.new(@context)
    attrs = landing.validate("pet" => @rex.section.slug, "name" => "Gastrointestinal Low Fat", "brand" => "Royal Canin",
      "form" => "prescription", "amount_per_day" => "310", "unit" => "g", "package_amount" => "12", "package_unit" => "kg",
      "package_cost" => "$104.99", "started_on" => "2026-08-12")

    food = landing.land!(attrs, sections: [])
    assert_equal @rex, food.pet
    assert_equal "Royal Canin Gastrointestinal Low Fat", food.display_name
    assert_equal "prescription", food.form
    assert_equal 10_499, food.package_cost_cents
    assert_equal 38, food.days_per_package
    assert_equal Date.new(2026, 8, 12), food.started_on
    assert_equal food, landing.duplicate_of("pet" => @rex.section.slug, "name" => "gastrointestinal low fat")
    assert_equal "Royal Canin Gastrointestinal Low Fat", landing.preview(attrs).title
  end

  test "the prompt block lists the pets, the people, and the care kinds the model may choose from" do
    @user.people.create!(name: "Dr. Alvarez", relationship: "Vet")
    block = Landing.prompt_block(@context)
    assert_includes block, "#{@rex.section.slug} — Rex, dog"
    assert_includes block, "— Dr. Alvarez — Vet"
    assert_includes block, "pet_vaccinations"
  end
end
