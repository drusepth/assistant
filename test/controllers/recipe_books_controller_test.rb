require "test_helper"

class RecipeBooksControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "every book page renders" do
    book = users(:one).recipe_books.create!(title: "Soups")
    book.recipe_book_entries.create!(recipe: users(:one).recipes.create!(title: "Pea soup"))
    users(:one).share_links.create!(subject: book)

    [ recipe_books_path, new_recipe_book_path, recipe_book_path(book), edit_recipe_book_path(book) ].each do |path|
      get path
      assert_response :success, path
    end
  end

  test "creates, updates, and deletes a book without touching its recipes" do
    assert_difference("RecipeBook.count") do
      post recipe_books_path, params: { recipe_book: { title: "Spring", description: "Light things" } }
    end
    book = RecipeBook.last
    assert_redirected_to recipe_book_path(book)

    recipe = users(:one).recipes.create!(title: "Pea soup")
    post add_recipes_recipe_book_path(book), params: { recipe_ids: [ recipe.id ] }
    assert_equal [ recipe.id ], book.reload.recipe_ids

    patch recipe_book_path(book), params: { recipe_book: { title: "Early spring" } }
    assert_equal "Early spring", book.reload.title

    assert_difference("RecipeBook.count", -1) { delete recipe_book_path(book) }
    assert Recipe.exists?(recipe.id), "deleting a book never deletes the recipes in it"
  end

  test "only my own recipes go into my book" do
    book = users(:one).recipe_books.create!(title: "Soups")
    mine = users(:one).recipes.create!(title: "Mine")
    bobs = users(:two).recipes.create!(title: "Bob's")

    post add_recipes_recipe_book_path(book), params: { recipe_ids: [ mine.id, bobs.id ] }

    assert_equal [ mine.id ], book.reload.recipe_ids
  end

  test "a book keeps the running order its owner dragged" do
    book = users(:one).recipe_books.create!(title: "Spring")
    first, second, third = %w[ Asparagus Peas Rhubarb ].map { |title| users(:one).recipes.create!(title: title) }
    post add_recipes_recipe_book_path(book), params: { recipe_ids: [ first.id, second.id, third.id ] }

    assert_equal [ first.id, second.id, third.id ], book.reload.recipe_book_entries.map(&:recipe_id)

    patch reorder_recipe_book_path(book), params: { recipe_ids: [ third.id, first.id, second.id ] }

    assert_equal [ third.id, first.id, second.id ], book.reload.recipe_book_entries.map(&:recipe_id)
    get recipe_book_path(book)
    assert_operator response.body.index("Rhubarb"), :<, response.body.index("Asparagus"),
      "the page reads in the order the owner set, not alphabetically"
  end

  test "a shared book is readable, and its recipes come with it" do
    book = users(:two).recipe_books.create!(title: "Bob's soups")
    recipe = users(:two).recipes.create!(title: "Chilli con carne")
    book.recipe_book_entries.create!(recipe: recipe)
    AccessGrant.create!(grantor: users(:two), grantee: users(:one), subject: book)

    get recipe_book_path(book)
    assert_response :success
    assert_match "Chilli con carne", response.body

    get recipe_path(recipe)
    assert_response :success
  end

  test "another household's book is not readable" do
    book = users(:outsider).recipe_books.create!(title: "Carol's")

    get recipe_book_path(book)
    assert_response :not_found
  end
end
