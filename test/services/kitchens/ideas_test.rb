require "test_helper"

class Kitchens::IdeasTest < ActiveSupport::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @kitchen = users(:one).kitchens.create!(name: "Home")
    @pantry = Kitchens::Pantry.new(@kitchen, by: users(:one))
    @pantry.add_lines("pasta\ntomatoes\ncream\nspinach\negg", location: "fridge")
    @kitchen.pantry_items.find_by(item_key: "spinach").update!(expires_on: Date.current + 1)

    @arrabbiata = recipe("Arrabbiata", "200 g pasta\n1 tin tomatoes", cooked: Date.current - 30)
    @florentine = recipe("Florentine", "200 g pasta\nspinach\ncream")
    @carbonara = recipe("Carbonara", "200 g pasta\n2 eggs\nparmesan\nguanciale")
    @quiche = recipe("Quiche", "spinach\n3 eggs\npastry")
    @tart = recipe("Tart", "pastry\ncream")
  end

  def recipe(title, text, cooked: nil)
    users(:one).recipes.create!(title: title, ingredients_text: text, last_cooked_on: cooked)
  end

  def ideas(**options) = Kitchens::Ideas.new(@kitchen, users(:one), **options)

  test "ready first, then missing one, then two — the one using what's going off leading its tier" do
    titles = ideas.ready_to_make.map { |candidate| candidate.recipe.title }

    assert_equal [ "Florentine", "Arrabbiata", "Quiche", "Tart", "Carbonara" ], titles
  end

  test "use it up: recipes using what expires soonest" do
    assert_equal [ "Florentine", "Quiche" ], ideas.use_it_up.map { |candidate| candidate.recipe.title }
  end

  test "buy to unlock: the one purchase that completes the most, then the next" do
    unlock = ideas.buy_to_unlock

    assert_equal "pastry", unlock.first.name
    assert_equal 2, unlock.first.ready, "pastry completes the quiche and the tart"
    assert_equal 1, unlock.first.using_soon
  end

  test "a diner's allergen leaves dishes out" do
    egg = @kitchen.foods.create!(name: "egg", allergens: [ "eggs" ])
    @kitchen.food_aliases.create!(key: "egg", food: egg)
    @kitchen.diners.create!(name: "Sam", allergens: [ "eggs" ])

    titles = ideas.candidates.map { |candidate| candidate.recipe.title }
    assert_not_includes titles, "Carbonara"
    assert_not_includes titles, "Quiche"
    assert_includes titles, "Arrabbiata"
  end

  test "the model picks among the ranked candidates, and its swaps stay suggestions" do
    stub_request(:post, ENDPOINT).to_return(status: 200, body: { choices: [ { message: { content: {
      recipe_id: @quiche.id, reason: "The spinach goes off tomorrow.",
      swaps: [ { missing: "pastry", use: "a potato base" }, { missing: "caviar", use: "anything" } ]
    }.to_json } } ] }.to_json)

    result = Kitchens::IdeasPick.new(ideas, profile: users(:one).household.model_profile).call

    assert_equal @quiche, result.recipe
    assert_equal [ [ "pastry", "a potato base" ] ], result.swaps, "a swap for something the recipe doesn't miss is dropped"
  end

  test "a pick outside the candidates is no pick" do
    stub_request(:post, ENDPOINT).to_return(status: 200, body: { choices: [ { message: { content: {
      recipe_id: 999_999, reason: "x"
    }.to_json } } ] }.to_json)

    assert_nil Kitchens::IdeasPick.new(ideas, profile: users(:one).household.model_profile).call
  end

  test "plan my week without a model fills free nights in ranked order, skipping planned ones" do
    @kitchen.meals.create!(date: Date.current, title: "Takeout")
    planner = Kitchens::WeekPlanner.new(@kitchen, users(:one))

    proposals = planner.propose(Date.current..(Date.current + 2))

    assert_equal [ Date.current + 1, Date.current + 2 ], proposals.map(&:date)
    assert_equal "Florentine", proposals.first.recipe.title
  end

  test "plan my week with a model keeps only valid nights and candidates" do
    stub_request(:post, ENDPOINT).to_return(status: 200, body: { choices: [ { message: { content: { nights: [
      { date: (Date.current + 1).iso8601, recipe_id: @quiche.id, reason: "Quick one." },
      { date: (Date.current + 1).iso8601, recipe_id: @tart.id },
      { date: (Date.current + 30).iso8601, recipe_id: @tart.id },
      { date: (Date.current + 2).iso8601, recipe_id: 999_999 }
    ] }.to_json } } ] }.to_json)

    proposals = Kitchens::WeekPlanner.new(@kitchen, users(:one), profile: users(:one).household.model_profile)
      .propose(Date.current..(Date.current + 2))

    assert_equal [ [ Date.current + 1, @quiche ] ], proposals.map { |proposal| [ proposal.date, proposal.recipe ] }
  end
end
