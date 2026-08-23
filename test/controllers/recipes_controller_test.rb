require "test_helper"

class RecipesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "every recipe page renders" do
    recipe = users(:one).recipes.create!(title: "Soup", servings: 4, ingredients_text: "200 g lentils")
    users(:one).share_links.create!(subject: recipe, label: "For Mum")

    [ recipes_path, new_recipe_path, recipe_path(recipe), edit_recipe_path(recipe) ].each do |path|
      get path
      assert_response :success, path
    end
  end

  test "the import page offers both doors" do
    get import_recipes_path
    assert_response :success
    assert_match "source_url", response.body
    assert_match "source_text", response.body
  end

  test "a pasted page lands as a recipe with the import queued" do
    assert_difference("Recipe.count") do
      assert_enqueued_with(job: ImportRecipeJob) do
        post import_recipes_path, params: { source_text: "Ingredients\n1 onion\nMethod\nCook it." }
      end
    end
    recipe = Recipe.last

    assert recipe.import_queued?
    assert_redirected_to recipe_path(recipe)
  end

  test "a link is kept for the job to fetch, and a non-link is refused up front" do
    post import_recipes_path, params: { source_url: "https://example.com/soup" }
    assert_equal "https://example.com/soup", Recipe.last.source_url

    assert_no_difference("Recipe.count") do
      post import_recipes_path, params: { source_url: "example dot com" }
    end
    assert_redirected_to import_recipes_path

    assert_no_difference("Recipe.count") do
      post import_recipes_path, params: { source_text: "", source_url: "" }
    end
  end

  test "our own envelope imports with no model call at all" do
    payload = {
      format: "assistant-recipe", version: 1,
      recipe: { title: "Lentil soup", servings: 4, ingredients: [ "200 g red lentils" ],
                directions: "Simmer it.", notes: "Freeze half." }
    }.to_json

    assert_no_enqueued_jobs(only: ImportRecipeJob) do
      post import_recipes_path, params: { source_text: payload }
    end
    recipe = Recipe.last

    assert_equal "Lentil soup", recipe.title
    assert_nil recipe.import_status
    assert_equal [ "200 g red lentils" ], recipe.recipe_ingredients.map(&:raw)
    assert_equal "red lentil", recipe.recipe_ingredients.first.item_key, "the receiving instance runs its own parser"
  end

  test "a share link from another assistant is asked for as JSON and comes across whole" do
    Web::Fetch.resolver = Class.new { def getaddresses(_host) = [ "93.184.216.34" ] }.new
    payload = {
      format: "assistant-recipe", version: 1,
      book: { title: "Grandma's" },
      recipes: [ { title: "Lentil soup", ingredients: [ "1 onion" ] }, { title: "Rhubarb cake" } ]
    }
    stub_request(:get, "https://sister.example/s/AAAAAAAAAAAAAAAAAAAAAAAA.json")
      .to_return(status: 200, headers: { "content-type" => "application/json" }, body: payload.to_json)

    assert_difference("Recipe.count", 2) do
      post import_recipes_path, params: { source_url: "https://sister.example/s/AAAAAAAAAAAAAAAAAAAAAAAA" }
    end

    book = RecipeBook.last
    assert_equal "Grandma's", book.title
    assert_equal 2, book.recipes.count
    assert_redirected_to recipe_book_path(book)
  ensure
    Web::Fetch.resolver = Resolv
  end

  test "a hostile envelope can't smuggle in anything but recipe fields" do
    payload = {
      format: "assistant-recipe", version: 1,
      recipe: { title: "Soup", user_id: users(:two).id, times_cooked: 999,
                source_url: "javascript:alert(1)", ingredients: [ "1 onion" ] }
    }.to_json

    post import_recipes_path, params: { source_text: payload }
    recipe = Recipe.last

    assert_equal users(:one).id, recipe.user_id
    assert_equal 0, recipe.times_cooked
    assert_nil recipe.source_url, "only http(s) links survive the envelope"
  end

  test "editing an imported recipe counts as reviewing it" do
    recipe = users(:one).recipes.create!(title: "Soup", import_status: :imported)

    patch recipe_path(recipe), params: { recipe: { title: "Lentil soup" } }

    assert_nil recipe.reload.import_status
  end

  test "creates a recipe from one paste, parsing the ingredients" do
    assert_difference("Recipe.count") do
      post recipes_path, params: { recipe: {
        title: "Lentil soup", servings: 4, prep_minutes: 10, cook_minutes: 30,
        ingredients_text: "200 g red lentils\n2 onions, chopped",
        directions: "Fry the onions.\nAdd the lentils."
      } }
    end
    recipe = Recipe.last

    assert_redirected_to recipe_path(recipe)
    assert_equal 2, recipe.recipe_ingredients.count
    assert_equal [ 200, "g" ], [ recipe.recipe_ingredients.first.quantity.to_i, recipe.recipe_ingredients.first.unit ]
  end

  test "the show page scales quantities from the servings parameter" do
    recipe = users(:one).recipes.create!(title: "Soup", servings: 4, ingredients_text: "200 g lentils")

    get recipe_path(recipe, servings: 8)

    assert_response :success
    assert_match "400 g lentils", response.body
  end

  test "an out-of-range servings parameter is clamped, not obeyed" do
    recipe = users(:one).recipes.create!(title: "Soup", servings: 4, ingredients_text: "200 g lentils")

    get recipe_path(recipe, servings: -5)
    assert_response :success
    assert_match "50 g lentils", response.body, "servings clamp to at least one"
  end

  test "cooking it logs one cook and comes back" do
    recipe = users(:one).recipes.create!(title: "Soup")

    post cook_recipe_path(recipe)

    assert_equal 1, recipe.reload.times_cooked
    assert_equal Date.current, recipe.last_cooked_on
  end

  test "search and section filters narrow the library" do
    health = sections(:health)
    soup = users(:one).recipes.create!(title: "Lentil soup", ingredients_text: "200 g lentils")
    soup.sections << health
    users(:one).recipes.create!(title: "Chocolate cake")

    get recipes_path(q: "lentil")
    assert_match "Lentil soup", response.body
    assert_no_match "Chocolate cake", response.body

    get recipes_path(section: health.slug)
    assert_match "Lentil soup", response.body
    assert_no_match "Chocolate cake", response.body
  end

  test "the library sorts the four ways a cook asks for" do
    old = users(:one).recipes.create!(title: "Zucchini soup", created_at: 2.years.ago, prep_minutes: 90)
    quick = users(:one).recipes.create!(title: "Beans on toast", prep_minutes: 5)
    quick.cooked!(Date.current)

    get recipes_path(sort: "quick")
    assert_operator response.body.index("Beans on toast"), :<, response.body.index("Zucchini soup")

    get recipes_path(sort: "recent")
    assert_operator response.body.index("Beans on toast"), :<, response.body.index("Zucchini soup")

    get recipes_path(sort: "never")
    assert_match "Zucchini soup", response.body
    assert_no_match(/Beans on toast/, response.body, "cooked once is not never cooked")

    get recipes_path(sort: "nonsense")
    assert_response :success, "an unknown sort falls back rather than blowing up"
  end

  test "a recipe shared with me is readable but not editable" do
    bobs = users(:two).recipes.create!(title: "Bob's chilli")
    AccessGrant.create!(grantor: users(:two), grantee: users(:one), subject: bobs)

    get recipe_path(bobs)
    assert_response :success
    assert_no_match edit_recipe_path(bobs), response.body

    patch recipe_path(bobs), params: { recipe: { title: "Mine now" } }
    assert_response :not_found
    assert_equal "Bob's chilli", bobs.reload.title
  end

  test "another household's recipe is not readable at all" do
    carols = users(:outsider).recipes.create!(title: "Carol's chilli")

    get recipe_path(carols)
    assert_response :not_found
  end

  test "a dish photo can come from the Photos library without copying the bytes" do
    recipe = users(:one).recipes.create!(title: "Soup")
    photo = users(:one).photos.create!(image: {
      io: File.open(file_fixture("photo.jpg")), filename: "photo.jpg", content_type: "image/jpeg"
    })

    assert_no_difference("ActiveStorage::Blob.count") do
      post attach_photo_recipe_path(recipe, photo_id: photo.id)
    end

    assert recipe.reload.image.attached?
    assert_equal photo.image.blob_id, recipe.image.blob_id, "the same blob, not a copy"
  end

  test "another member's photo can't be attached to my recipe" do
    recipe = users(:one).recipes.create!(title: "Soup")
    bobs = users(:two).photos.create!(image: {
      io: File.open(file_fixture("photo.jpg")), filename: "photo.jpg", content_type: "image/jpeg"
    })

    post attach_photo_recipe_path(recipe, photo_id: bobs.id)

    assert_response :not_found
    assert_not recipe.reload.image.attached?
  end

  test "adds to and removes from a book" do
    recipe = users(:one).recipes.create!(title: "Soup")
    book = users(:one).recipe_books.create!(title: "Soups")

    post add_to_book_recipe_path(recipe), params: { recipe_book_id: book.id }
    assert_equal [ recipe.id ], book.reload.recipe_ids

    delete remove_from_book_recipe_path(recipe), params: { recipe_book_id: book.id }
    assert_empty book.reload.recipe_ids
  end
end
