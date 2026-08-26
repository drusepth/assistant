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

  test "units convert across weights so a kilo bag can be fed in grams" do
    bag = @rex.pet_foods.create!(name: "Adult chicken", form: "dry", amount_per_day: 0.3, unit: "kg",
      package_amount: 12, package_cost_cents: 5_400, started_on: Date.current, opened_on: Date.current)

    assert_equal 40, bag.days_per_package
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
end
