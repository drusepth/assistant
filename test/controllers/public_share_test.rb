require "test_helper"

# The one unauthenticated read path in the app (D-share-link). What it must
# do: serve exactly the shared thing, to anyone holding the token, and
# nothing else — no session, no navigation, no neighbouring items, and no
# life beyond a revoke.
class PublicShareTest < ActionDispatch::IntegrationTest
  setup do
    @alice = users(:one)
    @recipe = @alice.recipes.create!(title: "Lentil soup", servings: 4,
      ingredients_text: "200 g red lentils", directions: "Simmer it.", notes: "Better the next day.")
    @link = @alice.share_links.create!(subject: @recipe)
  end

  test "a signed-out stranger with the token reads the recipe" do
    get shared_path(@link.token)

    assert_response :success
    assert_match "Lentil soup", response.body
    assert_match "200 g red lentils", response.body
    assert_match "Simmer it.", response.body
    assert_match "Better the next day.", response.body
  end

  test "the page names the sharer by first name only and carries no way in" do
    get shared_path(@link.token)

    assert_match "Shared by Alice", response.body
    assert_no_match(/Alice Smith/, response.body)
    assert_no_match(/one@example\.com/, response.body)
    assert_no_match(/href="\/recipes/, response.body, "no link back into the app")
    assert_no_match(/Sign out/, response.body)
  end

  test "it asks not to be indexed" do
    get shared_path(@link.token)

    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
  end

  test "the view is counted" do
    assert_difference -> { @link.reload.views_count } do
      get shared_path(@link.token)
    end
  end

  test "scaling works for the recipient too" do
    get shared_path(@link.token, servings: 8)

    assert_match "400 g red lentils", response.body
  end

  test "the same token, asked for as JSON, is a recipe another instance can import" do
    get shared_path(@link.token, format: :json)

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal "assistant-recipe", payload["format"]
    assert_equal "Lentil soup", payload.dig("recipe", "title")
    assert_equal [ "200 g red lentils" ], payload.dig("recipe", "ingredients")
    assert_not payload.to_s.include?("one@example.com"), "the envelope carries the recipe, not the household"
  end

  test "a book link exports the whole book, and a dead token exports nothing" do
    book = @alice.recipe_books.create!(title: "Soups")
    book.recipe_book_entries.create!(recipe: @recipe)
    link = @alice.share_links.create!(subject: book)

    get shared_path(link.token, format: :json)
    payload = JSON.parse(response.body)

    assert_equal "Soups", payload.dig("book", "title")
    assert_equal [ "Lentil soup" ], payload["recipes"].map { |row| row["title"] }

    get shared_path("nope", format: :json)
    assert_response :not_found
  end

  test "an unknown, revoked, or expired token gives nothing away" do
    get shared_path("not-a-real-token")
    assert_response :not_found

    @link.destroy!
    get shared_path(@link.token)
    assert_response :not_found

    expired = @alice.share_links.create!(subject: @recipe, expires_at: 1.hour.ago)
    get shared_path(expired.token)
    assert_response :not_found
  end

  test "a book link serves the book and, under the same token, its recipes" do
    book = @alice.recipe_books.create!(title: "Soups")
    book.recipe_book_entries.create!(recipe: @recipe)
    other = @alice.recipes.create!(title: "Not in the book")
    link = @alice.share_links.create!(subject: book)

    get shared_path(link.token)
    assert_response :success
    assert_match "Lentil soup", response.body
    assert_no_match(/Not in the book/, response.body, "only what's in the book travels with it")

    get shared_path(link.token, recipe: @recipe.id)
    assert_response :success
    assert_match "200 g red lentils", response.body

    get shared_path(link.token, recipe: other.id)
    assert_response :not_found, "the token opens the book's recipes and no others"
  end

  test "a book link never publishes a recipe its owner doesn't own" do
    book = @alice.recipe_books.create!(title: "Soups")
    carols = users(:outsider).recipes.create!(title: "Carol's chilli")
    RecipeBookEntry.insert_all([ { recipe_book_id: book.id, recipe_id: carols.id,
      created_at: Time.current, updated_at: Time.current } ])
    link = @alice.share_links.create!(subject: book)

    get shared_path(link.token)
    assert_response :success
    assert_no_match(/chilli/i, response.body)

    get shared_path(link.token, recipe: carols.id)
    assert_response :not_found
  end
end

class ShareLinksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @alice = users(:one)
    @recipe = @alice.recipes.create!(title: "Lentil soup")
    sign_in_as @alice
  end

  test "creates a link with a label and an expiry, then revokes it" do
    assert_difference("ShareLink.count") do
      post share_links_path, params: { subject_type: "Recipe", subject_id: @recipe.id,
        label: "For Mum", expires_in_days: "7" }
    end
    link = ShareLink.last

    assert_equal "For Mum", link.label
    assert_in_delta 7.days.from_now.to_f, link.expires_at.to_f, 60

    assert_difference("ShareLink.count", -1) { delete share_link_path(link) }
  end

  test "a link can only be minted for something you own" do
    bobs = users(:two).recipes.create!(title: "Bob's chilli")

    assert_no_difference("ShareLink.count") do
      post share_links_path, params: { subject_type: "Recipe", subject_id: bobs.id }
    end
    assert_response :not_found
  end

  test "the subject type is allowlisted at the door" do
    note = @alice.notes.create!(body: "Not for the public")

    assert_no_difference("ShareLink.count") do
      post share_links_path, params: { subject_type: "Note", subject_id: note.id }
    end
    assert_response :not_found
  end

  test "someone else's link can't be revoked" do
    bobs_recipe = users(:two).recipes.create!(title: "Chilli")
    link = users(:two).share_links.create!(subject: bobs_recipe)

    assert_no_difference("ShareLink.count") { delete share_link_path(link) }
    assert_response :not_found
  end
end
