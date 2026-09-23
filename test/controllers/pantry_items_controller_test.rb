require "test_helper"

class PantryItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @kitchen = users(:one).kitchens.create!(name: "Home")
    users(:one).update!(current_kitchen: @kitchen)
    sign_in_as users(:one)
  end

  test "the three tabs, adding, editing, moving and using up" do
    post kitchen_pantry_items_path(@kitchen), params: { location: "fridge", lines: "cream\nspinach, half a bag" }
    cream = @kitchen.pantry_items.find_by!(item_key: "cream")

    Food::LOCATIONS.each_key do |location|
      get kitchen_pantry_items_path(@kitchen, location: location)
      assert_response :success
    end

    patch kitchen_pantry_item_path(@kitchen, cream), params: { pantry_item: { expires_on: Date.current + 1, opened_on: Date.current } }
    get kitchen_pantry_items_path(@kitchen, location: "fridge")
    assert_match "use by tomorrow", response.body

    patch move_kitchen_pantry_item_path(@kitchen, cream, location: "freezer")
    assert_equal "freezer", cream.reload.location

    post add_to_list_kitchen_pantry_item_path(@kitchen, cream)
    assert_equal [ "cream" ], ShoppingList.default_for(@kitchen).items.pluck(:item)

    delete kitchen_pantry_item_path(@kitchen, cream)
    assert_not PantryItem.exists?(cream.id)
  end

  test "the hub warns about what's going off" do
    Kitchens::Pantry.new(@kitchen, by: users(:one)).add_lines("cream", location: "fridge").first.update!(expires_on: Date.current)

    get section_path("food")
    assert_match "Use soon", response.body
    assert_match "use today", response.body
  end

  test "the recipe page counts what's in, and the list gets only what's missing" do
    recipe = users(:one).recipes.create!(title: "Pasta", servings: 2, ingredients_text: "200 g pasta\n1 tin tomatoes")
    Kitchens::Pantry.new(@kitchen, by: users(:one)).add_lines("pasta", location: "pantry")

    get recipe_path(recipe)
    assert_match "1 of 2", response.body

    post recipe_list_addition_path(recipe, servings: 2)
    assert_equal [ "tomatoes" ], ShoppingList.default_for(@kitchen).items.pluck(:item)
  end

  test "cooking offers to take out what the recipe used" do
    recipe = users(:one).recipes.create!(title: "Pasta", ingredients_text: "200 g pasta\n1 tin tomatoes")
    pasta = Kitchens::Pantry.new(@kitchen, by: users(:one)).add_lines("pasta", location: "pantry").first

    post cook_recipe_path(recipe)
    assert_redirected_to new_recipe_use_up_path(recipe)
    follow_redirect!
    assert_match "Anything used up?", response.body

    post recipe_use_up_path(recipe), params: { pantry_item_ids: [ pasta.id ] }
    assert_not PantryItem.exists?(pasta.id)
  end

  test "someone else's kitchen is out of reach" do
    theirs = users(:two).kitchens.create!(name: "Bob's")

    get kitchen_pantry_items_path(theirs)
    assert_response :not_found
  end
end
