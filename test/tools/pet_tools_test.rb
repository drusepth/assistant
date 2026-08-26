require "test_helper"

# W5 of docs/PETS_PLAN.md: the pet tools, and the three guarantees that don't
# depend on the model behaving.
class PetToolsTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @rex = create_pet(user: @user, breed: "Golden retriever", born_on: 4.years.ago.to_date,
      microchip: "985141000123456", color: "Golden, white chest")
  end

  def run_for(slug, **inputs)
    @user.tool_runs.create!(tool_slug: slug, inputs: inputs.transform_keys(&:to_s), status: :queued)
  end

  test "a pet tool reads her record instead of asking for it" do
    @rex.pet_foods.create!(name: "Adult chicken", brand: "Acme", form: "dry", amount_per_day: 300,
      unit: "g", package_amount: 12_000, started_on: 1.year.ago.to_date)
    @rex.pet_foods.create!(name: "Puppy formula", form: "dry", unit: "g",
      started_on: 3.years.ago.to_date, ended_on: 1.year.ago.to_date)
    med = @user.notes.create!(kind: Note::MEDICATION, title: "Apoquel 16mg", body: "half a tablet daily")
    med.sections << @rex.section
    visit = @user.events.create!(title: "Rex — vaccinations", starts_at: 2.months.ago)
    visit.sections << @rex.section

    prompt = Tool::VetVisitPrep.new(run_for("vet_visit_prep", pet_id: @rex.id)).send(:user_prompt)

    assert_match "Species: Dog", prompt
    assert_match "Breed: Golden retriever", prompt
    assert_match "4 years old", prompt
    assert_match "Currently eating:", prompt
    assert_match "Acme Adult chicken", prompt
    assert_match "Previously eaten (the diet history a vet asks for):", prompt
    assert_match "Puppy formula", prompt
    assert_match "Apoquel 16mg", prompt
    assert_match "Rex — vaccinations", prompt
  end

  test "the lost-pet sheet spells out the poster facts, and says when the chip is missing" do
    prompt = Tool::LostPet.new(run_for("lost_pet", pet_id: @rex.id)).send(:user_prompt)
    assert_match "Microchip number: 985141000123456", prompt
    assert_match "Colour and markings: Golden, white chest", prompt

    @rex.update!(microchip: nil)
    assert_match "MICROCHIP: not recorded in the app",
      Tool::LostPet.new(run_for("lost_pet", pet_id: @rex.id)).send(:user_prompt)
  end

  test "a pet tool's draft files under her lens as well as its section" do
    tool = Tool::VetVisitPrep.new(run_for("vet_visit_prep", pet_id: @rex.id))
    filing = tool.send(:filing)

    assert_includes filing, @rex.section
    assert_includes filing, sections(:health)
  end

  test "a pet that vanished or was unshared raises rather than drafting about nothing" do
    run = run_for("vet_visit_prep", pet_id: @rex.id)
    @rex.destroy!

    assert_raises(Llm::Error) { Tool::VetVisitPrep.new(run).send(:user_prompt) }
  end

  test "comparing a policy with itself is refused before any model call" do
    document = @user.documents.create!(title: "Policy", extracted_text: "Some cover.")
    run = run_for("compare_pet_insurance", policy_a_id: document.id, policy_b_id: document.id)

    error = assert_raises(Llm::Error) { Tool::ComparePetInsurance.new(run).send(:user_prompt) }
    assert_match "same document", error.message
  end

  # ── The guardrails ────────────────────────────────────────────────────

  test "every pet_care session opens with a code-authored emergency notice" do
    assert_match "Go to a vet now", Tool::PetCare::EMERGENCY_NOTICE
    assert_match "(888) 426-4435", Tool::PetCare::EMERGENCY_NOTICE
  end

  test "a toxin the owner names is answered by a lookup, before the model speaks" do
    run = run_for("pet_care", pet_id: @rex.id)
    run.tool_run_messages.create!(role: :user, content: "Can he have some chocolate?")

    Tool::PetCare.new(run).send(:warn_about_toxics)

    notice = run.tool_run_messages.notice_role.sole
    assert_match "Not safe for a dog", notice.content
    assert_match "Theobromine", notice.content
    assert_match Datasets::PetToxics::POISON_LINE, notice.content
  end

  test "the toxics list is species-aware, and doesn't fire on a longer word" do
    toxics = Datasets::PetToxics.current

    assert_equal %w[ lilies ], toxics.scan("lilies on the table", species: "cat").map(&:item)
    assert_empty toxics.scan("lilies on the table", species: "dog"),
      "a lily is a cat emergency; claiming it for a dog would teach the owner to ignore this"
    assert_empty toxics.scan("grapefruit for breakfast", species: "dog"),
      "word boundaries, or every fruit bowl is an emergency"
  end

  test "an ordinary question adds no notice at all" do
    run = run_for("pet_care", pet_id: @rex.id)
    run.tool_run_messages.create!(role: :user, content: "How often should I brush her?")

    Tool::PetCare.new(run).send(:warn_about_toxics)
    assert_empty run.tool_run_messages.notice_role
  end

  test "a missing toxics file leaves an empty list rather than taking the chat down" do
    toxics = Datasets::PetToxics.new(path: nil)
    assert_equal 0, toxics.size
    assert_empty toxics.scan("chocolate", species: "dog")
  end

  # ── The Act zone ──────────────────────────────────────────────────────

  test "the care tools are hidden until the household has a pet, but arrival never is" do
    assert_empty Pets.hidden_tool_slugs(@user)

    @rex.destroy!
    hidden = Pets.hidden_tool_slugs(@user)
    assert_includes hidden, "vet_visit_prep"
    assert_not_includes hidden, "new_pet", "it is how the first one arrives"
  end

  test "a pet who has died stops being offered to the tools" do
    @rex.update!(died_on: Date.current)
    assert_includes Pets.hidden_tool_slugs(@user), "pet_care"
  end
end
