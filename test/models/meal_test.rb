require "test_helper"

class MealTest < ActiveSupport::TestCase
  setup do
    @kitchen = users(:one).kitchens.create!(name: "Home")
    @recipe = users(:one).recipes.create!(title: "Chilli", servings: 4, ingredients_text: "500 g mince\n1 tin tomatoes")
  end

  test "a planned recipe carries its title; a free line needs one" do
    assert_equal "Chilli", @kitchen.meals.create!(date: Date.current, recipe: @recipe).title
    assert @kitchen.meals.create!(date: Date.current, slot: "lunch", title: "Leftovers").persisted?
    assert_not @kitchen.meals.new(date: Date.current).valid?
  end

  test "the recipe opens only for someone who can see it" do
    meal = @kitchen.meals.create!(date: Date.current, recipe: @recipe)

    assert_equal @recipe, meal.recipe_for(users(:one))
    assert_nil meal.recipe_for(users(:two))
  end

  test "slots read in the order of a day" do
    @kitchen.meals.create!(date: Date.current, slot: "dinner", title: "Chilli")
    @kitchen.meals.create!(date: Date.current, slot: "breakfast", title: "Toast")

    assert_equal %w[ breakfast dinner ], @kitchen.meals.in_order.pluck(:slot)
  end

  test "the week's list: scaled, minus the kitchen, once per meal" do
    list = ShoppingList.default_for(@kitchen)
    Kitchens::Pantry.new(@kitchen, by: users(:one)).add_lines("tomatoes", location: "pantry")
    meal = @kitchen.meals.create!(date: Date.current, recipe: @recipe, servings: 8)
    week = Date.current..(Date.current + 6)

    result = Kitchens::WeekList.new(@kitchen, list, by: users(:one)).call(week)
    assert_equal [ 1, 1 ], [ result.meals, result.lines ]
    assert_equal [ "1000 g mince" ], list.items.map(&:display)

    assert_equal 0, Kitchens::WeekList.new(@kitchen, list, by: users(:one)).call(week).meals

    meal.update!(servings: 4)
    Kitchens::WeekList.new(@kitchen, list, by: users(:one)).call(week)
    assert_equal [ "1500 g mince" ], list.items.reload.map(&:display), "a changed meal is listed again"
  end

  test "past meals aren't shopped for" do
    @kitchen.meals.create!(date: Date.current - 1, recipe: @recipe)

    result = Kitchens::WeekList.new(@kitchen, ShoppingList.default_for(@kitchen), by: users(:one))
      .call((Date.current - 3)..(Date.current + 3))
    assert_equal 0, result.meals
  end
end
