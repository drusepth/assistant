require "test_helper"

class CategorizeRecipeJobTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @recipe = users(:one).recipes.create!(
      title: "No-salt lentil soup",
      description: "The one the cardiologist would approve of.",
      source_name: "Grandma",
      ingredients_text: "200 g red lentils\n2 carrots, diced\nno salt",
      notes: "Skip the stock cube — that's where the sodium hides."
    )
  end

  test "files the recipe into sections" do
    stub_llm(sections: [ "health", "people", "not-a-real-slug" ])

    CategorizeRecipeJob.perform_now(@recipe)

    assert_equal [ sections(:health), sections(:people) ], @recipe.reload.sections.to_a
  end

  test "sends the recipe and the taxonomy to the model" do
    stub_llm(sections: [])

    CategorizeRecipeJob.perform_now(@recipe)

    assert_requested(:post, ENDPOINT) do |request|
      content = JSON.parse(request.body)["messages"].last["content"]
      content.include?("No-salt lentil soup") && content.include?("200 g red lentils") &&
        content.include?("Grandma") && content.include?("renting — Rights · Renting")
    end
  end

  test "skips recipes the cook already tagged, without calling the provider" do
    @recipe.sections << sections(:health)

    CategorizeRecipeJob.perform_now(@recipe)

    assert_not_requested :post, ENDPOINT
  end

  test "does nothing without a configured model profile" do
    recipe = users(:outsider).recipes.create!(title: "No AI here")

    CategorizeRecipeJob.perform_now(recipe)

    assert_not_requested :post, ENDPOINT
  end

  test "provider errors leave the recipe unfiled instead of raising" do
    stub_request(:post, ENDPOINT).to_return(status: 500, body: "boom")

    CategorizeRecipeJob.perform_now(@recipe)

    assert_empty @recipe.reload.sections
  end

  private
    def stub_llm(sections:)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: { sections: sections }.to_json } } ] }.to_json
      )
    end
end
