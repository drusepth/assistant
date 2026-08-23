require "test_helper"

# Private by default (D9), shared three ways: a per-item grant, a grant on a
# book that contains it (the album clause, D-recipe-primitive), and a public
# link (D-share-link) — which is *not* part of visible_to and never widens
# what a signed-in user can see.
class RecipeVisibilityTest < ActiveSupport::TestCase
  setup do
    @alice = users(:one)
    @bob = users(:two)
    @carol = users(:outsider)
    @book = @alice.recipe_books.create!(title: "Soups")
    @in_book = @alice.recipes.create!(title: "Lentil soup")
    @book.recipe_book_entries.create!(recipe: @in_book)
    @loose = @alice.recipes.create!(title: "Secret cake")
  end

  test "no grant, no visibility" do
    assert_empty Recipe.visible_to(@bob)
    assert_empty RecipeBook.visible_to(@bob)
    assert_equal [ @in_book, @loose ].sort_by(&:id), Recipe.visible_to(@alice).order(:id).to_a
  end

  test "an item grant exposes exactly that recipe" do
    AccessGrant.create!(grantor: @alice, grantee: @bob, subject: @loose)

    assert_includes Recipe.visible_to(@bob), @loose
    assert_not_includes Recipe.visible_to(@bob), @in_book
  end

  test "a book grant exposes the book and the recipes in it" do
    AccessGrant.create!(grantor: @alice, grantee: @bob, subject: @book)

    assert_includes RecipeBook.visible_to(@bob), @book
    assert_includes Recipe.visible_to(@bob), @in_book
    assert_not_includes Recipe.visible_to(@bob), @loose, "recipes outside the book stay private"
  end

  test "recipes added to a granted book later are covered; removed ones are not" do
    AccessGrant.create!(grantor: @alice, grantee: @bob, subject: @book)
    late = @alice.recipes.create!(title: "Minestrone")
    @book.recipe_book_entries.create!(recipe: late)

    assert late.visible_to?(@bob)

    @book.recipe_book_entries.where(recipe: late).destroy_all
    assert_not late.reload.visible_to?(@bob)
  end

  test "a section grant covers recipes tagged with that section" do
    health = sections(:health)
    @loose.sections << health
    AccessGrant.create!(grantor: @alice, grantee: @bob, subject: health)

    assert_includes Recipe.visible_to(@bob), @loose
  end

  test "revoking the book grant hides the book and its recipes again" do
    grant = AccessGrant.create!(grantor: @alice, grantee: @bob, subject: @book)
    grant.destroy!

    assert_not @book.visible_to?(@bob)
    assert_not @in_book.visible_to?(@bob)
  end

  test "the grantor guard: a book can never leak a recipe its owner didn't put there" do
    # Q-recipe-collab groundwork — force a foreign recipe into Alice's book.
    carols = @carol.recipes.create!(title: "Carol's chilli")
    RecipeBookEntry.insert_all([ { recipe_book_id: @book.id, recipe_id: carols.id,
      created_at: Time.current, updated_at: Time.current } ])
    AccessGrant.create!(grantor: @alice, grantee: @bob, subject: @book)

    assert_not_includes Recipe.visible_to(@bob), carols,
      "Alice's grant must not expose Carol's recipe — the grantor isn't its owner"
  end

  test "grants can't cross households" do
    grant = AccessGrant.new(grantor: @alice, grantee: @carol, subject: @loose)

    assert_not grant.valid?
    assert_includes grant.errors[:grantee], "must be in the same household"
  end

  test "a public link does not add to what a signed-in stranger can see" do
    @alice.share_links.create!(subject: @loose)

    assert_empty Recipe.visible_to(@bob)
  end
end
