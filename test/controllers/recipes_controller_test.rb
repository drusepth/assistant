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

  test "adds to and removes from a book" do
    recipe = users(:one).recipes.create!(title: "Soup")
    book = users(:one).recipe_books.create!(title: "Soups")

    post add_to_book_recipe_path(recipe), params: { recipe_book_id: book.id }
    assert_equal [ recipe.id ], book.reload.recipe_ids

    delete remove_from_book_recipe_path(recipe), params: { recipe_book_id: book.id }
    assert_empty book.reload.recipe_ids
  end
end
