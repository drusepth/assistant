require "test_helper"

class IdeasControllerTest < ActionDispatch::IntegrationTest
  setup do
    @kitchen = users(:one).kitchens.create!(name: "Home")
    users(:one).update!(current_kitchen: @kitchen)
    Kitchens::Pantry.new(@kitchen, by: users(:one)).add_lines("pasta\ntomatoes", location: "pantry")
    @recipe = users(:one).recipes.create!(title: "Arrabbiata", ingredients_text: "200 g pasta\n1 tin tomatoes\nchilli")
    sign_in_as users(:one)
  end

  test "the ideas page and the hub" do
    get kitchen_ideas_path(@kitchen)
    assert_response :success
    assert_match "Arrabbiata", response.body
    assert_match "Buy to unlock", response.body
    assert_enqueued_with(job: IdeasPickJob)

    get section_path("food")
    assert_match "Ideas", response.body
    assert_match "chilli", response.body
  end

  test "plan my week: a proposal, then only the ticked nights land" do
    # An empty arrangement falls back to the ranked order.
    stub_request(:post, "https://api.openai.com/v1/chat/completions").to_return(status: 200,
      body: { choices: [ { message: { content: { nights: [] }.to_json } } ] }.to_json)
    post propose_kitchen_meals_path(@kitchen, week: Date.current)
    assert_response :success
    assert_match "Arrabbiata", response.body
    assert_equal 0, @kitchen.meals.count

    post accept_kitchen_meals_path(@kitchen), params: { nights: {
      "0" => { date: Date.current.iso8601, recipe_id: @recipe.id, plan: "1" },
      "1" => { date: (Date.current + 1).iso8601, recipe_id: @recipe.id, plan: "0" }
    } }
    assert_equal [ Date.current ], @kitchen.meals.pluck(:date)
  end

  test "diners in the kitchen settings" do
    post kitchen_diners_path(@kitchen), params: { diner: { user_id: users(:one).id, name: "", allergens: [ "", "peanuts" ], diet_note: "vegetarian" } }
    diner = @kitchen.diners.sole
    assert_equal [ "Alice Smith", [ "peanuts" ] ], [ diner.name, diner.allergens ]

    get edit_kitchen_path(@kitchen)
    assert_match "no peanuts", response.body

    patch kitchen_diner_path(@kitchen, diner), params: { diner: { allergens: [ "" ] } }
    assert_empty diner.reload.allergens

    delete kitchen_diner_path(@kitchen, diner)
    assert_empty @kitchen.diners
  end
end
