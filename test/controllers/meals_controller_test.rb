require "test_helper"

class MealsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @kitchen = users(:one).kitchens.create!(name: "Home")
    users(:one).update!(current_kitchen: @kitchen)
    @recipe = users(:one).recipes.create!(title: "Chilli", servings: 4, ingredients_text: "500 g mince")
    sign_in_as users(:one)
  end

  test "plan, see it on the week, the hub and the calendar, move it, clear it" do
    post kitchen_meals_path(@kitchen), params: { meal: { date: Date.current, slot: "dinner", recipe_id: @recipe.id } }
    meal = @kitchen.meals.sole
    assert_equal "Chilli", meal.title

    get kitchen_meals_path(@kitchen)
    assert_response :success
    assert_match "Chilli", response.body

    get section_path("food")
    assert_match "This week", response.body
    assert_match "Chilli", response.body

    get calendar_path
    assert_match "Chilli", response.body

    patch kitchen_meal_path(@kitchen, meal), params: { meal: { date: Date.current + 1, cook_id: users(:one).id } }
    assert_equal [ Date.current + 1, users(:one) ], [ meal.reload.date, meal.cook ]

    delete kitchen_meal_path(@kitchen, meal)
    assert_not Meal.exists?(meal.id)
  end

  test "a free line, and the week's list" do
    post kitchen_meals_path(@kitchen), params: { meal: { date: Date.current, title: "Takeout" } }
    post kitchen_meals_path(@kitchen), params: { meal: { date: Date.current + 1, recipe_id: @recipe.id } }

    post make_list_kitchen_meals_path(@kitchen)
    assert_equal [ "500 g mince" ], ShoppingList.default_for(@kitchen).items.map(&:display)
  end

  test "a recipe, cook or event the planner can't see is dropped, not planned" do
    bobs = users(:two).recipes.create!(title: "Bob's secret")

    post kitchen_meals_path(@kitchen), params: { meal: { date: Date.current, recipe_id: bobs.id, title: "Something",
      cook_id: users(:outsider).id } }

    meal = @kitchen.meals.sole
    assert_nil meal.recipe
    assert_nil meal.cook
  end

  test "a partner the kitchen is shared with plans too; others can't" do
    users(:one).granted_access_grants.create!(grantee: users(:two), subject: @kitchen)
    sign_in_as users(:two)
    post kitchen_meals_path(@kitchen), params: { meal: { date: Date.current, title: "Pizza night" } }
    assert_equal 1, @kitchen.meals.count

    sign_in_as users(:outsider)
    get kitchen_meals_path(@kitchen)
    assert_response :not_found
  end
end
