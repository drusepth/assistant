require "test_helper"

class FoodWatchersTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @kitchen = @user.kitchens.create!(name: "Home")
    @pantry = Kitchens::Pantry.new(@kitchen, by: @user)
  end

  def recipe(title, text) = @user.recipes.create!(title: title, ingredients_text: text)

  test "pantry expiry: one nudge per kitchen for what's going off that a recipe uses" do
    recipe("Gratin", "cream\npotatoes")
    cream = @pantry.add_lines("cream", location: "fridge").first
    cream.update!(expires_on: Date.current + 1)
    @pantry.add_lines("mustard", location: "fridge").first.update!(expires_on: Date.current + 1)

    suggestion = Watcher::PantryExpiry.new(@user).scan.sole
    assert_match "The cream goes off", suggestion.title
    assert_equal "/kitchens/#{@kitchen.id}/ideas", suggestion.path_action
    assert_includes suggestion.sections, sections(:food)
    assert_not Watcher::PantryExpiry.new(@user).resolved?(suggestion)

    cream.move_to!("freezer")
    assert Watcher::PantryExpiry.new(@user).resolved?(suggestion)
  end

  test "pantry expiry stays quiet about things no recipe uses" do
    @pantry.add_lines("mustard", location: "fridge").first.update!(expires_on: Date.current)

    assert_empty Watcher::PantryExpiry.new(@user).scan
  end

  test "meal plan gap only speaks to a kitchen that plans" do
    assert_empty Watcher::MealPlanGap.new(@user).scan

    @kitchen.meals.create!(date: Date.current - 14, title: "Soup")
    @kitchen.meals.create!(date: Date.current - 7, title: "Stew")
    suggestion = Watcher::MealPlanGap.new(@user).scan.sole
    assert_equal "/kitchens/#{@kitchen.id}/plan", suggestion.path_action

    3.times { |day| @kitchen.meals.create!(date: Date.current + day, title: "Planned") }
    assert_no_difference("Suggestion.count") { Watcher::MealPlanGap.new(@user).scan }
  end

  test "meal needs: a planned dinner missing things that aren't listed; retires once they're bought" do
    chilli = recipe("Chilli", "500 g mince\n1 tin tomatoes\n1 onion")
    meal = @kitchen.meals.create!(date: Date.current + 1, recipe: chilli)
    @pantry.add_lines("onion", location: "pantry")
    ShoppingList.default_for(@kitchen).add_lines("tomatoes", by: @user)

    suggestion = Watcher::MealNeeds.new(@user).scan.sole
    assert_match "needs mince", suggestion.title
    assert_match "mince", suggestion.body
    assert_no_match "tomatoes", suggestion.body

    @pantry.add_lines("mince", location: "fridge")
    assert Watcher::MealNeeds.new(@user).resolved?(suggestion)

    meal.destroy!
    assert Watcher::MealNeeds.new(@user).resolved?(suggestion)
  end

  test "recipe rut: the same few dinners for weeks, and something saved and never made" do
    rotation = 3.times.map { |index| recipe("Usual #{index}", "rice") }
    untried = recipe("Something new", "squash")
    12.times { |index| @kitchen.meals.create!(date: Date.current - (index + 1) * 3, recipe: rotation[index % 3]) }

    suggestion = Watcher::RecipeRut.new(@user).scan.sole
    assert_match "Something new", suggestion.body
    assert_equal "/recipes/#{untried.id}", suggestion.path_action
  end

  test "a kitchen shared with you counts, one you can't see doesn't" do
    theirs = users(:two).kitchens.create!(name: "Bob's")
    Kitchens::Pantry.new(theirs, by: users(:two)).add_lines("cream", location: "fridge").first.update!(expires_on: Date.current)
    recipe("Gratin", "cream")

    assert_empty Watcher::PantryExpiry.new(@user).scan

    users(:two).granted_access_grants.create!(grantee: @user, subject: theirs)
    assert_equal 1, Watcher::PantryExpiry.new(@user).scan.size
  end
end
