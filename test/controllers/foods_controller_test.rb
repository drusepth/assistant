require "test_helper"

class FoodsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @kitchen = users(:one).kitchens.create!(name: "Home")
    @list = ShoppingList.default_for(@kitchen)
    sign_in_as users(:one)
  end

  def food(name, key: name, **attributes)
    @kitchen.foods.create!(name: name, **attributes).tap { |food| @kitchen.food_aliases.create!(key: key, food: food) }
  end

  test "the catalog, a food, and a fix" do
    milk = food("milk", aisle: "dairy")
    @list.add_lines("milk", by: users(:one))

    get kitchen_foods_path(@kitchen)
    assert_response :success
    assert_match "Dairy &amp; eggs", response.body

    get edit_kitchen_food_path(@kitchen, milk)
    assert_response :success

    patch kitchen_food_path(@kitchen, milk), params: { food: { name: "whole milk", aisle: "dairy", default_location: "fridge", allergens: [ "", "milk" ] } }
    assert_equal [ "whole milk", "fridge", [ "milk" ] ], [ milk.reload.name, milk.default_location, milk.allergens ]
  end

  test "merging two foods" do
    scallion = food("scallion")
    spring = food("spring onion")
    @list.add_lines("scallions", by: users(:one))

    post merge_kitchen_food_path(@kitchen, scallion), params: { target_id: spring.id }

    assert_not Food.exists?(scallion.id)
    assert_equal spring, @list.items.sole.food
  end

  test "the list reads in the household's aisle order" do
    food("milk", aisle: "dairy")
    food("apple", aisle: "produce")
    @list.add_lines("milk\napples", by: users(:one))

    3.times { patch move_aisle_kitchen_foods_path(@kitchen, aisle: "dairy", direction: "up") }
    assert_equal "dairy", @kitchen.reload.aisles_in_order.first

    get kitchen_shopping_list_path(@kitchen, @list)
    assert_operator response.body.index("Dairy &amp; eggs"), :<, response.body.index("Fruit &amp; veg")
  end

  test "someone else's kitchen's foods are out of reach" do
    theirs = users(:two).kitchens.create!(name: "Bob's")
    bread = theirs.foods.create!(name: "bread")

    get edit_kitchen_food_path(theirs, bread)
    assert_response :not_found
  end
end
