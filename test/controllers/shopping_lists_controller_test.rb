require "test_helper"

class ShoppingListsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @kitchen = users(:one).kitchens.create!(name: "Home")
    @list = ShoppingList.default_for(@kitchen)
    sign_in_as users(:one)
  end

  test "the hub and the in-store page show the list" do
    @list.add_lines("2 tins chickpeas", by: users(:one))

    get section_path("food")
    assert_response :success
    assert_match "2 cans chickpeas", response.body

    get kitchen_shopping_list_path(@kitchen, @list)
    assert_response :success
    assert_match "In the basket", response.body
  end

  test "quick-add, check, uncheck and remove" do
    post kitchen_shopping_list_items_path(@kitchen, @list), params: { lines: "milk\n3 lemons" }
    assert_equal 2, @list.items.count
    milk = @list.items.find_by(item_key: "milk")

    patch check_kitchen_shopping_list_item_path(@kitchen, @list, milk), headers: { "X-Optimistic" => "1" }
    assert_response :no_content
    assert milk.reload.checked?
    assert_equal users(:one), milk.checked_by

    patch uncheck_kitchen_shopping_list_item_path(@kitchen, @list, milk)
    assert_response :redirect
    assert_not milk.reload.checked?

    delete kitchen_shopping_list_item_path(@kitchen, @list, milk)
    assert_not ShoppingListItem.exists?(milk.id)
  end

  test "retyping a line re-parses it" do
    item = @list.add_lines("lemons", by: users(:one)).first

    patch kitchen_shopping_list_item_path(@kitchen, @list, item), params: { line: "3 lemons, unwaxed" }

    assert_equal "3 lemons", item.reload.display
    assert_equal "unwaxed", item.note
  end

  test "a partner the kitchen is shared with can add and check off" do
    users(:one).granted_access_grants.create!(grantee: users(:two), subject: @kitchen)
    sign_in_as users(:two)

    post kitchen_shopping_list_items_path(@kitchen, @list), params: { lines: "bread" }
    item = @list.items.sole
    assert_equal users(:two), item.added_by

    patch check_kitchen_shopping_list_item_path(@kitchen, @list, item)
    assert item.reload.checked?
  end

  test "nobody else can touch an unshared kitchen's list" do
    item = @list.add_lines("bread", by: users(:one)).first
    sign_in_as users(:two)

    get kitchen_shopping_list_path(@kitchen, @list)
    assert_response :not_found
    patch check_kitchen_shopping_list_item_path(@kitchen, @list, item)
    assert_response :not_found
    assert_not item.reload.checked?
  end

  test "more lists: make, rename, delete" do
    post kitchen_shopping_lists_path(@kitchen), params: { shopping_list: { name: "Costco" } }
    costco = @kitchen.shopping_lists.find_by!(name: "Costco")
    assert_redirected_to kitchen_shopping_list_path(@kitchen, costco)

    patch kitchen_shopping_list_path(@kitchen, costco), params: { shopping_list: { name: "Bulk" } }
    assert_equal "Bulk", costco.reload.name

    delete kitchen_shopping_list_path(@kitchen, costco)
    assert_not ShoppingList.exists?(costco.id)
  end

  test "a recipe's ingredients go on the list, scaled, and remember the recipe" do
    recipe = users(:one).recipes.create!(title: "Chilli", servings: 4,
      ingredients_text: "500 g mince\n1 tin tomatoes\nFor the top:\nsour cream (optional)")

    post recipe_list_addition_path(recipe, servings: 8)

    items = @list.items.reload
    assert_equal [ "1000 g mince", "2 cans tomatoes" ], items.map(&:display)
    assert items.all? { |item| item.recipe == recipe }
  end
end
