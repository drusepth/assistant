require "test_helper"

class Foods::CatalogTest < ActiveSupport::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  test "with no model, each new wording is its own food — the same words match, nothing else" do
    kitchen = users(:outsider).kitchens.create!(name: "Home")
    users(:outsider).recipes.create!(title: "Soup", ingredients_text: "2 spring onions\n1 onion")
    list = ShoppingList.default_for(kitchen)
    list.add_lines("scallions\nonions", by: users(:outsider))

    catalog = Foods::Catalog.new(kitchen)
    assert_not catalog.model?
    catalog.resolve!

    assert_equal [ "onion", "scallion", "spring onion" ], kitchen.foods.order(:name).pluck(:name)
    assert_equal kitchen.foods.find_by(name: "onion"), list.items.find_by(item_key: "onion").reload.food
    assert_not_requested :post, ENDPOINT
  end

  test "the model files new wordings onto existing foods, new foods, and each other" do
    kitchen = users(:one).kitchens.create!(name: "Home")
    spring = kitchen.foods.create!(name: "spring onion", aisle: "produce")
    kitchen.food_aliases.create!(key: "spring onion", food: spring)
    chicken = kitchen.foods.create!(name: "chicken", aisle: "meat")
    list = ShoppingList.default_for(kitchen)
    list.add_lines("scallions\nchicken thighs\ngreen onions\ntahini", by: users(:one))

    stub_request(:post, ENDPOINT).to_return(status: 200, body: {
      choices: [ { message: { content: { foods: [
        { line: 1, same_as: spring.id },
        { line: 2, name: "chicken thighs", aisle: "meat", location: "fridge", kind_of: chicken.id },
        { line: 3, same_as_line: 1 },
        { line: 4, name: "tahini", aisle: "not-an-aisle", allergens: [ "sesame", "gluten" ], same_as: 999_999, staple: "yes" }
      ] }.to_json } } ]
    }.to_json)

    Foods::Catalog.new(kitchen).resolve!

    by_key = list.items.reload.index_by(&:item_key)
    assert_equal spring, by_key["scallion"].food
    assert_equal spring, by_key["green onion"].food
    thighs = by_key["chicken thigh"].food
    assert_equal [ "chicken thighs", "meat", "fridge", chicken ], [ thighs.name, thighs.aisle, thighs.default_location, thighs.kind_of ]
    tahini = by_key["tahini"].food
    assert_nil tahini.aisle, "an aisle outside the set is dropped"
    assert_equal [ "sesame" ], tahini.allergens
    assert_not tahini.staple?, "only a literal true makes a staple"
    assert tahini.filed_at

    assert_requested(:post, ENDPOINT) do |request|
      content = JSON.parse(request.body)["messages"].last["content"]
      content.include?("#{spring.id} — spring onion") && content.include?("1. scallions")
    end
  end

  test "a wording is asked about once per kitchen, ever" do
    kitchen = users(:one).kitchens.create!(name: "Home")
    food = kitchen.foods.create!(name: "milk")
    kitchen.food_aliases.create!(key: "milk", food: food)
    ShoppingList.default_for(kitchen).add_lines("milk", by: users(:one))

    assert_not Foods::Catalog.new(kitchen).unresolved?
    Foods::Catalog.new(kitchen).resolve!
    assert_not_requested :post, ENDPOINT
  end

  test "the catalog page lists only foods reached through something the viewer can see" do
    kitchen = users(:one).kitchens.create!(name: "Home")
    users(:one).granted_access_grants.create!(grantee: users(:two), subject: kitchen)
    users(:one).recipes.create!(title: "Private", ingredients_text: "prenatal vitamins")
    users(:two).recipes.create!(title: "Bob's", ingredients_text: "sardines")
    ShoppingList.default_for(kitchen).add_lines("bread", by: users(:one))
    [ "prenatal vitamin", "sardine", "bread" ].each do |key|
      kitchen.food_aliases.create!(key: key, food: kitchen.foods.create!(name: key))
    end

    catalog = Foods::Catalog.new(kitchen)
    assert_equal %w[ bread sardine ], catalog.visible_foods(users(:two)).order(:name).pluck(:name)
    assert_equal [ "bread", "prenatal vitamin" ], catalog.visible_foods(users(:one)).order(:name).pluck(:name)
  end
end
