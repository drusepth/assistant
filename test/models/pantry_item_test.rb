require "test_helper"

class PantryItemTest < ActiveSupport::TestCase
  setup do
    @kitchen = users(:one).kitchens.create!(name: "Home")
    @pantry = Kitchens::Pantry.new(@kitchen, by: users(:one))
  end

  test "typed lines land in one place, and what's already there isn't doubled" do
    @pantry.add_lines("2 tins chickpeas\nmilk, the big one", location: "pantry")
    @pantry.add_lines("chickpeas", location: "pantry")

    rows = @kitchen.pantry_items.order(:item).to_a
    assert_equal [ "chickpeas", "milk" ], rows.map(&:item)
    assert_equal [ "2 cans", "the big one" ], rows.map(&:quantity_note)
  end

  test "checking a line off puts it away, and un-checking takes it back out" do
    milk = @kitchen.foods.create!(name: "milk", default_location: "fridge")
    @kitchen.food_aliases.create!(key: "milk", food: milk)
    line = ShoppingList.default_for(@kitchen).add_lines("2 l milk", by: users(:one)).first

    line.check!(by: users(:two))
    row = @kitchen.pantry_items.sole
    assert_equal [ "fridge", milk, "2 l", users(:two) ], [ row.location, row.food, row.quantity_note, row.added_by ]

    line.uncheck!
    assert_empty @kitchen.pantry_items.reload
  end

  test "un-checking never removes what was already in the kitchen" do
    @pantry.add_lines("bread", location: "pantry")
    line = ShoppingList.default_for(@kitchen).add_lines("bread", by: users(:one)).first

    line.check!(by: users(:one))
    line.uncheck!

    assert_equal 1, @kitchen.pantry_items.count
  end

  test "a kitchen can switch putting away off" do
    @kitchen.update!(put_away_on_check: false)
    ShoppingList.default_for(@kitchen).add_lines("bread", by: users(:one)).first.check!(by: users(:one))

    assert_empty @kitchen.pantry_items
  end

  test "freezing stops the clock" do
    row = @pantry.add_lines("mince", location: "fridge").first
    row.update!(expires_on: Date.current + 1)

    row.move_to!("freezer")

    assert_nil row.reload.expires_on
  end

  test "expiring is within two days, soonest first" do
    later = @pantry.add_lines("yoghurt", location: "fridge").first.tap { |row| row.update!(expires_on: Date.current + 2) }
    sooner = @pantry.add_lines("cream", location: "fridge").first.tap { |row| row.update!(expires_on: Date.current) }
    @pantry.add_lines("butter", location: "fridge").first.update!(expires_on: Date.current + 10)

    assert_equal [ sooner, later ], @kitchen.pantry_items.expiring.by_expiry.to_a
  end
end
