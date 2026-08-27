require "test_helper"

class PetFoodTest < ActiveSupport::TestCase
  setup { @rex = create_pet }

  def food(**attributes)
    @rex.pet_foods.create!({
      name: "Adult chicken", form: "dry", amount_per_day: 300, unit: "g",
      package_amount: 12_000, package_cost_cents: 5_400, started_on: Date.current, opened_on: Date.current
    }.merge(attributes))
  end

  test "a bag divided by a daily amount is a reorder date, not a guess" do
    bag = food(unit: "g", amount_per_day: 300, package_amount: 12_000, opened_on: Date.current)

    assert_equal 40, bag.days_per_package
    assert_equal Date.current + 40, bag.runs_out_on
  end

  test "units convert across weights, in either direction" do
    kilos = @rex.pet_foods.create!(name: "Adult chicken", form: "dry", amount_per_day: 0.3, unit: "kg",
      package_amount: 12, package_unit: "kg", package_cost_cents: 5_400, started_on: Date.current, opened_on: Date.current)
    mixed = @rex.pet_foods.create!(name: "Same food", form: "dry", amount_per_day: 300, unit: "g",
      package_amount: 12, package_unit: "kg", started_on: Date.current, opened_on: Date.current)

    assert_equal 40, kilos.days_per_package
    assert_equal 40, mixed.days_per_package
  end

  test "counted units never convert — a bag in cans fed in scoops says nothing" do
    bag = @rex.pet_foods.create!(name: "Tins", form: "wet", amount_per_day: 2, unit: "cans",
      package_amount: 24, started_on: Date.current, opened_on: Date.current)

    assert_nil bag.days_per_package, "a can is not a gram, and inventing a density is worse than saying nothing"
    assert_nil bag.runs_out_on
  end

  test "no opened date means no reorder claim" do
    bag = food(opened_on: nil)

    assert_equal 40, bag.days_per_package
    assert_nil bag.runs_out_on, "counting from `started_on` drifts a bag further out every month"
  end

  test "a month of food is the bag's price over its days, never rounded to one bag" do
    bag = food(package_cost_cents: 5_400)

    # 40-day bag: 30.44/40 of $54.
    assert_equal 4_109, bag.monthly_cost_cents
    assert_nil food(package_cost_cents: nil, name: "Unpriced").monthly_cost_cents
  end

  test "ending a food keeps it, which is what makes a diet history" do
    old = food(name: "Puppy formula", started_on: 1.year.ago.to_date)
    old.update!(ended_on: Date.current)

    assert_equal [ old ], @rex.pet_foods.past.to_a
    assert_empty @rex.pet_foods.current.to_a
  end

  test "a bag carries its own unit, because a sack is sold in kilos and fed in grams" do
    bag = @rex.pet_foods.create!(name: "Adult chicken", form: "dry", amount_per_day: 300, unit: "g",
      package_amount: 12, package_unit: "kg", started_on: Date.current, opened_on: Date.current)

    assert_equal 40, bag.days_per_package
    assert_equal "300g a day", bag.daily_phrase
    assert_equal "12kg", bag.package_phrase
  end

  test "a package that wouldn't last a day says nothing rather than 'today'" do
    # 12 kilos typed as 12 grams: the old shared-unit form made this easy, and
    # the answer used to be a confident reorder date of today.
    bag = food(package_amount: 12, package_unit: "g")

    assert_nil bag.days_per_package
    assert_nil bag.runs_out_on
    assert_nil bag.monthly_cost_cents
  end

  test "mismatched counted units still have no answer" do
    bag = @rex.pet_foods.create!(name: "Tins", form: "wet", amount_per_day: 200, unit: "g",
      package_amount: 24, package_unit: "cans", started_on: Date.current, opened_on: Date.current)

    assert_nil bag.days_per_package, "a can is not a gram"
  end
end
