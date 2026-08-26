require "test_helper"

class Pets::FoodShelfTest < ActiveSupport::TestCase
  setup { @rex = create_pet }

  def food(**attributes)
    @rex.pet_foods.create!({
      name: "Adult chicken", form: "dry", amount_per_day: 300, unit: "g",
      package_amount: 12_000, package_cost_cents: 5_400, started_on: Date.current, opened_on: Date.current
    }.merge(attributes))
  end

  test "the monthly total sums what can be priced, and says when it is partial" do
    food(package_cost_cents: 5_400)
    food(name: "Dental sticks", form: "treats", package_cost_cents: nil)

    shelf = Pets::FoodShelf.new(@rex)
    assert_equal 4_109, shelf.monthly_cost_cents
    assert shelf.partial_cost?, "a total that silently means 'the priced ones' would read as the whole bill"
  end

  test "with nothing priced the total is nil rather than zero" do
    food(package_cost_cents: nil)
    assert_nil Pets::FoodShelf.new(@rex).monthly_cost_cents
  end

  test "running out is the week ahead, soonest first" do
    soon = food(name: "Nearly gone", opened_on: 38.days.ago.to_date)
    food(name: "Fresh bag", opened_on: Date.current)

    assert_equal [ soon ], Pets::FoodShelf.new(@rex).running_out.map { |food| food }
  end

  test "a food with no reorder date can never be 'running out'" do
    food(name: "Tins", unit: "cans", amount_per_day: 2, package_amount: 24, opened_on: 1.year.ago.to_date)

    assert_empty Pets::FoodShelf.new(@rex).running_out
  end
end
