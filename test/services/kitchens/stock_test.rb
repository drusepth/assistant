require "test_helper"

class Kitchens::StockTest < ActiveSupport::TestCase
  setup do
    @kitchen = users(:one).kitchens.create!(name: "Home")
    @recipe = users(:one).recipes.create!(title: "Stew",
      ingredients_text: "500 g chicken\n2 spring onions\n1 tin tomatoes\nFor the top:\nparsley (optional)")
  end

  def food(name, *keys, **attributes)
    @kitchen.foods.create!(name: name, **attributes).tap do |food|
      ([ name ] + keys).each { |key| @kitchen.food_aliases.create!(key: key, food: food) }
    end
  end

  test "a line is had when its food is in, under any wording, or a kind of it is" do
    chicken = food("chicken")
    food("chicken thigh", kind_of: chicken)
    food("spring onion", "scallion")
    pantry = Kitchens::Pantry.new(@kitchen, by: users(:one))
    pantry.add_lines("chicken thighs\nscallions", location: "fridge")
    Foods::Catalog.new(@kitchen).backfill!

    have, need = Kitchens::Stock.new(@kitchen).split(@recipe)

    assert_equal [ "chicken", "spring onions" ], have.map(&:item)
    assert_equal [ "tomatoes" ], need.map(&:item), "optional and divider lines never count"
  end

  test "a general food in the kitchen doesn't satisfy a specific recipe line" do
    food("chicken")
    thighs = food("chicken thigh")
    thighs.update!(kind_of: @kitchen.foods.find_by(name: "chicken"))
    recipe = users(:one).recipes.create!(title: "Thighs", ingredients_text: "6 chicken thighs")
    Kitchens::Pantry.new(@kitchen, by: users(:one)).add_lines("chicken", location: "fridge")
    Foods::Catalog.new(@kitchen).backfill!

    assert_empty Kitchens::Stock.new(@kitchen).split(recipe).first
  end

  test "an unfiled line still matches the same words" do
    Kitchens::Pantry.new(@kitchen, by: users(:one)).add_lines("1 tin tomatoes", location: "pantry")

    assert_equal [ "tomatoes" ], Kitchens::Stock.new(@kitchen).split(@recipe).first.map(&:item)
  end

  test "a staple is always had, and never needs buying" do
    food("tomato").update!(staple: false)
    salt = food("salt", staple: true)
    recipe = users(:one).recipes.create!(title: "Salted", ingredients_text: "salt\n1 tomato")

    have, need = Kitchens::Stock.new(@kitchen).split(recipe)
    assert_equal [ "salt" ], have.map(&:item)
    assert_equal [ "tomato" ], need.map(&:item)
    assert salt.staple?
  end
end
