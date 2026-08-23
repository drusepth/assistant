require "test_helper"

# Paste-import (RECIPES_PLAN §5.1). The division of labour is the thing
# under test: the model finds the recipe inside the page, and the app's own
# parser reads the numbers, so an imported recipe and a typed one are the
# same object.
class ImportRecipeJobTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  PAGE = <<~TEXT.freeze
    My grandmother's kitchen smelled of woodsmoke and I have 800 words about it.

    Ingredients
    200 g red lentils
    2 large onions, finely chopped
    For the topping:
    handful of parsley

    Method
    Soften the onions.
    Add the lentils and simmer.

    Comments
    First! Great recipe.
  TEXT

  setup { @alice = users(:one) }

  test "a pasted page becomes a filled-in recipe whose numbers came from our parser" do
    stub_llm(
      title: "Lentil soup", servings: "4 servings", prep_minutes: 10, cook_minutes: "30 mins",
      ingredients: [ "200 g red lentils", "2 large onions, finely chopped", "For the topping:", "handful of parsley" ],
      directions: [ "Soften the onions.", "Add the lentils and simmer." ],
      notes: "Better the next day.", source_name: "Grandma"
    )
    recipe = @alice.recipes.create!(title: "Importing…", import_source: PAGE)

    ImportRecipeJob.perform_now(recipe)

    recipe.reload
    assert recipe.import_imported?
    assert_equal "Lentil soup", recipe.title
    assert_equal [ 4, 10, 30 ], [ recipe.servings, recipe.prep_minutes, recipe.cook_minutes ]
    assert_equal 4, recipe.recipe_ingredients.count
    lentils = recipe.recipe_ingredients.first
    assert_equal [ 200, "g", "red lentil" ], [ lentils.quantity.to_i, lentils.unit, lentils.item_key ]
    assert_equal [ "For the topping" ], recipe.recipe_ingredients.select(&:heading?).map(&:item)
    assert_equal 2, recipe.steps.size
    assert_nil recipe.import_error
  end

  test "the prompt is sent the recipe, not the memoir or the comments" do
    stub_llm(title: "Lentil soup", ingredients: [ "200 g red lentils" ], directions: [ "Simmer." ])
    ImportRecipeJob.perform_now(@alice.recipes.create!(title: "Importing…", import_source: PAGE))

    assert_requested(:post, ENDPOINT) do |request|
      content = JSON.parse(request.body)["messages"].last["content"]
      content.include?("200 g red lentils") && !content.include?("800 words") && !content.include?("First!")
    end
  end

  test "a link is fetched by the app, not by the model, and kept for a retry" do
    stub_request(:get, "https://example.com/soup").to_return(
      status: 200, headers: { "content-type" => "text/html" },
      body: "<html><head><title>Soup</title></head><body>#{PAGE}</body></html>"
    )
    stub_llm(title: "Lentil soup", ingredients: [ "200 g red lentils" ], directions: [ "Simmer." ])
    recipe = @alice.recipes.create!(title: "Importing…", source_url: "https://example.com/soup")

    ImportRecipeJob.perform_now(recipe)

    assert_requested :get, "https://example.com/soup"
    assert recipe.reload.import_imported?
    assert_match "200 g red lentils", recipe.import_source
  end

  test "with no model configured the deterministic splitter still finds the seams" do
    model_profiles(:smith).update!(api_key: "")
    recipe = @alice.recipes.create!(title: "Importing…", import_source: PAGE)

    ImportRecipeJob.perform_now(recipe)

    recipe.reload
    assert recipe.import_imported?
    assert_equal [ "200 g red lentils", "2 large onions, finely chopped", "For the topping:", "handful of parsley" ],
      recipe.recipe_ingredients.map(&:raw)
    assert_match "Soften the onions.", recipe.directions
    assert_no_match(/First!/, recipe.directions, "the comment mine is not the method")
  end

  test "a failed import says so on the recipe instead of leaving it spinning" do
    stub_request(:post, ENDPOINT).to_return(status: 401, body: { error: { message: "Incorrect API key" } }.to_json)
    recipe = @alice.recipes.create!(title: "Importing…", import_source: PAGE)

    ImportRecipeJob.perform_now(recipe)

    recipe.reload
    assert recipe.import_failed?
    assert_match "401", recipe.import_error
  end

  test "a model that finds no recipe fails honestly rather than inventing one" do
    stub_llm(title: "")
    recipe = @alice.recipes.create!(title: "Importing…", import_source: "A page about tractors.")

    ImportRecipeJob.perform_now(recipe)

    assert recipe.reload.import_failed?
    assert_equal 0, recipe.recipe_ingredients.count
  end

  private
    def stub_llm(**payload)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: payload.to_json } } ] }.to_json,
        headers: { "content-type" => "application/json" }
      )
    end
end
