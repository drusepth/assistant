require "test_helper"

class ShareLinksHelperTest < ActionView::TestCase
  test "renders an offline SVG QR of the link" do
    svg = share_link_qr("https://home.example/s/AAAAAAAAAAAAAAAAAAAAAAAA")

    assert_match "<svg", svg
    assert_match "viewBox", svg
    assert svg.html_safe?
  end
end

class RecipesHelperTest < ActionView::TestCase
  test "an unpictured recipe gets a stable warm monogram rather than a grey icon" do
    soup = users(:one).recipes.create!(title: "Mum's lentil soup")
    cake = users(:one).recipes.create!(title: "Rhubarb cake")

    assert_equal "ML", recipe_monogram(soup)
    assert_equal "RC", recipe_monogram(cake)
    assert_equal recipe_tile_classes(soup), recipe_tile_classes(Recipe.new(title: "mum's lentil soup")),
      "the same soup is the same colour every time"
    assert_includes RecipesHelper::TILE_TINTS, recipe_tile_classes(cake)
  end

  test "a title with no letters still gets a tile" do
    assert_equal "?", recipe_monogram(Recipe.new(title: "!!!"))
  end
end
