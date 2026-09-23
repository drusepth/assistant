require "test_helper"

class FoodTest < ActiveSupport::TestCase
  setup do
    @kitchen = users(:one).kitchens.create!(name: "Home")
  end

  test "aisles, locations and allergens come from closed sets" do
    food = @kitchen.foods.create!(name: "tahini", aisle: "condiments", default_location: "pantry",
      allergens: [ "sesame", "made-up", "" ])

    assert_equal [ "sesame" ], food.allergens
    assert_not @kitchen.foods.new(name: "x", aisle: "moon").valid?
  end

  test "kind of is one level, in this kitchen" do
    chicken = @kitchen.foods.create!(name: "chicken")
    thighs = @kitchen.foods.create!(name: "chicken thighs", kind_of: chicken)

    assert_not @kitchen.foods.new(name: "boneless thighs", kind_of: thighs).valid?
    other = users(:two).kitchens.create!(name: "Bob's").foods.create!(name: "chicken")
    assert_not @kitchen.foods.new(name: "wings", kind_of: other).valid?
  end

  test "a merge moves the wording and the rows, and sticks" do
    list = ShoppingList.default_for(@kitchen)
    scallion = @kitchen.foods.create!(name: "scallion", allergens: [])
    spring = @kitchen.foods.create!(name: "spring onion", aisle: "produce")
    @kitchen.food_aliases.create!(key: "scallion", food: scallion)
    @kitchen.food_aliases.create!(key: "spring onion", food: spring)
    line = list.items.create!(item: "scallions", item_key: "scallion", food: scallion)

    scallion.merge_into!(spring)

    assert_not Food.exists?(scallion.id)
    assert_equal spring, line.reload.food
    assert_equal spring, Foods::Catalog.new(@kitchen).foods_by_key([ "scallion" ])["scallion"]
  end
end
