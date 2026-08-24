require "test_helper"

class RecipeTest < ActiveSupport::TestCase
  setup { @alice = users(:one) }

  test "requires a title" do
    recipe = @alice.recipes.new
    assert_not recipe.valid?
    assert_includes recipe.errors[:title], "can't be blank"
  end

  # The source link is rendered as an href on a page strangers can open
  # (the share link), so the scheme is checked where every write path meets.
  test "a source link has to be a link" do
    recipe = @alice.recipes.new(title: "Soup", source_url: "javascript:alert(document.cookie)")

    assert_not recipe.valid?
    assert_includes recipe.errors[:source_url], "needs to start with http:// or https://"
  end

  test "http, https, and no link at all are all fine" do
    assert @alice.recipes.new(title: "Soup", source_url: "https://example.com/soup").valid?
    assert @alice.recipes.new(title: "Soup", source_url: "http://example.com/soup").valid?
    assert @alice.recipes.new(title: "Soup").valid?
  end

  test "assigning ingredients_text parses rows and reading it hands the lines back" do
    recipe = @alice.recipes.create!(title: "Soup", ingredients_text: "200 g red lentils\n2 large onions, finely chopped\nsalt to taste")

    assert_equal 3, recipe.recipe_ingredients.count
    lentils, onions, salt = recipe.recipe_ingredients.to_a

    assert_equal [ 200, "g", "red lentils" ], [ lentils.quantity.to_i, lentils.unit, lentils.item ]
    assert_equal "finely chopped", onions.note
    assert_equal "onion", onions.item_key
    assert_nil salt.quantity, "an unquantified line is a perfectly good ingredient"
    assert_equal "200 g red lentils\n2 large onions, finely chopped\nsalt to taste", recipe.reload.ingredients_text
  end

  test "re-assigning ingredients_text replaces the rows rather than appending" do
    recipe = @alice.recipes.create!(title: "Soup", ingredients_text: "1 onion\n2 carrots")
    recipe.update!(ingredients_text: "1 onion")

    assert_equal [ "1 onion" ], recipe.reload.recipe_ingredients.map(&:raw)
  end

  test "saving without touching ingredients_text leaves the rows alone" do
    recipe = @alice.recipes.create!(title: "Soup", ingredients_text: "1 onion")
    recipe.update!(title: "Better soup")

    assert_equal [ "1 onion" ], recipe.reload.recipe_ingredients.map(&:raw)
  end

  test "headings ride along in the list but never in what you shop for" do
    recipe = @alice.recipes.create!(title: "Lasagne", ingredients_text: "For the sauce:\n2 onions\nFor the pasta:\n300 g flour")

    assert_equal 4, recipe.recipe_ingredients.count
    assert_equal [ "For the sauce", "For the pasta" ], recipe.recipe_ingredients.select(&:heading?).map(&:item)
    assert_equal [ "onion", "flour" ], recipe.shoppable_ingredients.map(&:item_key)
    assert_equal "For the sauce:\n2 onions\nFor the pasta:\n300 g flour", recipe.reload.ingredients_text
  end

  test "steps split on blank lines when there are any, otherwise on newlines" do
    single = @alice.recipes.create!(title: "A", directions: "Chop.\nFry.\nEat.")
    assert_equal [ "Chop.", "Fry.", "Eat." ], single.steps

    blocked = @alice.recipes.create!(title: "B", directions: "1. Chop\nthe onion.\n\n2. Fry it.")
    assert_equal [ "Chop\nthe onion.", "Fry it." ], blocked.steps,
      "existing numbering is stripped so it isn't rendered twice"
  end

  test "scaling multiplies quantities and leaves unquantified lines alone" do
    recipe = @alice.recipes.create!(title: "Soup", servings: 4,
      ingredients_text: "200 g lentils\nsalt to taste")
    factor = recipe.scale_factor(6)

    assert_in_delta 1.5, factor
    assert_equal "300 g lentils", recipe.recipe_ingredients.first.display(factor)
    assert_equal "salt to taste", recipe.recipe_ingredients.last.display(factor)
  end

  test "scaling a recipe with no serving count is a no-op" do
    recipe = @alice.recipes.create!(title: "Soup", ingredients_text: "200 g lentils")

    assert_equal 1.0, recipe.scale_factor(8)
  end

  test "cooking it logs the date and the count, and nothing else" do
    recipe = @alice.recipes.create!(title: "Soup")

    recipe.cooked!(Date.new(2026, 3, 1))
    recipe.cooked!(Date.new(2026, 3, 8))

    assert_equal 2, recipe.times_cooked
    assert_equal Date.new(2026, 3, 8), recipe.last_cooked_on
  end

  test "search matches titles, descriptions, and ingredients" do
    soup = @alice.recipes.create!(title: "Lentil soup", ingredients_text: "200 g red lentils")
    cake = @alice.recipes.create!(title: "Cake", description: "Grandma's", ingredients_text: "100 g flour")

    assert_equal [ soup ], Recipe.search("lentil").to_a
    assert_equal [ cake ], Recipe.search("grandma").to_a
    assert_equal [ cake ], Recipe.search("flour").to_a
    assert_empty Recipe.search("chorizo")
  end

  test "deleting a recipe takes its ingredients and book entries with it" do
    recipe = @alice.recipes.create!(title: "Soup", ingredients_text: "1 onion")
    book = @alice.recipe_books.create!(title: "Soups")
    book.recipe_book_entries.create!(recipe: recipe)

    assert_difference [ "RecipeIngredient.count", "RecipeBookEntry.count" ], -1 do
      recipe.destroy!
    end
    assert RecipeBook.exists?(book.id), "the book outlives the recipe"
  end
end
