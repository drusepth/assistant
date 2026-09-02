require "test_helper"

# The drift guard (D-landing-registry): the registry is the one list of
# what a model may propose and code may write, and these tests are what
# make it stay that way. A new kind that isn't registered, or a new
# primitive nobody decided about, fails here — not in production, quietly.
class Landing::RegistryTest < ActiveSupport::TestCase
  setup { Rails.application.eager_load! }

  test "every landing kind is registered" do
    defined = Landing::Base.descendants.map(&:kind).sort
    assert_equal Landing::KINDS.sort, defined,
      "a Landing::Base subclass exists that Landing::KINDS doesn't list (or the reverse)"
  end

  test "every kind declares what it is, what it produces, and at least one required field" do
    Landing.all.each do |kind|
      assert kind.description.present?, "#{kind.kind} has no description"
      assert kind.produces.present?, "#{kind.kind} doesn't say which primitive it produces"
      assert kind.fields.any?(&:required?), "#{kind.kind} has no required field, so nothing anchors its fingerprint"
    end
  end

  test "every primitive the user can export is either produced by a kind or excused with a reason" do
    produced = Landing.all.map(&:produces).uniq
    Users::Export::MODELS.each_key do |key|
      next if produced.include?(key)

      assert Landing::NOT_INTAKE.key?(key),
        "#{key} is exported but no landing kind produces it and Landing::NOT_INTAKE doesn't say why"
      assert Landing::NOT_INTAKE[key].present?, "#{key} is excused without a reason"
    end
  end

  test "nothing is both produced and excused" do
    both = Landing.all.map(&:produces) & Landing::NOT_INTAKE.keys
    assert_empty both, "#{both.join(", ")}: pick one"
  end

  test "the prompt block names every kind and every field, and lists the household's references" do
    user = users(:one)
    rex = create_pet(user: user)
    block = Landing.prompt_block(Landing::Context.new(user: user))

    Landing.all.each do |kind|
      assert_includes block, "- #{kind.kind} — "
      kind.fields.each { |field| assert_includes block, field.name }
    end
    assert_includes block, "at most #{Landing::MAX_LANDINGS}"
    assert_includes block, "#{rex.section.slug} — Rex, dog" if Landing.all.flat_map(&:fields).any? { |field| field.ref == :pet }
  end

  test "propose validates into the closed set: unknown kinds and entries missing a required field are dropped" do
    context = Landing::Context.new(user: users(:one))
    proposed = Landing.propose([
      { "kind" => "event", "title" => "Rex — vaccinations", "on" => "2026-08-12", "surprise" => "dropped" },
      { "kind" => "event", "title" => "No date" },
      { "kind" => "spaceship", "title" => "Not a kind" },
      { "kind" => "task", "title" => "Call the vet", "due_on" => "not a date" },
      "garbage",
      { "kind" => "event", "title" => "Rex — vaccinations", "on" => "2026-08-12" }
    ], context)

    assert_equal %w[ event task ], proposed.map { |entry| entry["kind"] }
    assert_equal({ "title" => "Rex — vaccinations", "on" => "2026-08-12" }, proposed.first["attributes"])
    assert_equal "event:rex-vaccinations:2026-08-12", proposed.first["fingerprint"]
    assert_equal "proposed", proposed.first["status"]
    # A malformed optional field is dropped, not the entry.
    assert_equal({ "title" => "Call the vet" }, proposed.last["attributes"])
  end

  test "propose is capped" do
    context = Landing::Context.new(user: users(:one))
    many = (1..30).map { |i| { "kind" => "note", "title" => "Fact #{i}" } }
    assert_equal Landing::MAX_LANDINGS, Landing.propose(many, context).size
  end
end
