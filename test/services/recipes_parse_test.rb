require "test_helper"

# The parser is what lets capture stay a paste (D-recipe-primitive): every
# shape a person actually writes an ingredient in has to come out as
# quantity/unit/item without a model call.
class RecipesParseTest < ActiveSupport::TestCase
  test "plain quantity, unit, and item" do
    assert_parses "200 g flour", quantity: 200, unit: "g", item: "flour", item_key: "flour"
  end

  test "unit aliases collapse to one canonical spelling" do
    %w[ tbsp tablespoon tablespoons Tbsp. tbs ].each do |written|
      assert_equal "tbsp", Recipes::Parse.line_attributes("2 #{written} olive oil")[:unit], written
    end
  end

  test "mixed numbers, vulgar fractions, and plain fractions" do
    assert_in_delta 1.5, Recipes::Parse.line_attributes("1 1/2 cups milk")[:quantity]
    assert_in_delta 0.5, Recipes::Parse.line_attributes("½ tsp cumin")[:quantity]
    assert_in_delta 2.25, Recipes::Parse.line_attributes("2¼ cups flour")[:quantity]
    assert_in_delta 0.75, Recipes::Parse.line_attributes("3/4 cup sugar")[:quantity]
  end

  test "a range takes the low end — a shopping list has to name one number" do
    assert_in_delta 2.0, Recipes::Parse.line_attributes("2-3 cloves garlic")[:quantity]
    assert_in_delta 2.0, Recipes::Parse.line_attributes("2 to 3 apples")[:quantity]
  end

  test "no quantity at all is a perfectly good ingredient" do
    parsed = Recipes::Parse.line_attributes("salt and pepper to taste")

    assert_nil parsed[:quantity]
    assert_nil parsed[:unit]
    assert_equal "salt and pepper to taste", parsed[:item]
  end

  test "the note after the first comma is preparation, not part of the name" do
    parsed = Recipes::Parse.line_attributes("2 large onions, finely chopped")

    assert_equal "large onions", parsed[:item]
    assert_equal "finely chopped", parsed[:note]
    assert_equal "onion", parsed[:item_key], "descriptors and plurals come off the match key"
  end

  test "optional is read from either spelling and dropped from the item" do
    [ "handful of parsley (optional)", "handful of parsley, optional" ].each do |line|
      parsed = Recipes::Parse.line_attributes(line)
      assert parsed[:optional], line
      assert_equal "parsley", parsed[:item], line
    end
  end

  test "bullets and 'of' are noise" do
    parsed = Recipes::Parse.line_attributes("- 1 cup of rice")

    assert_equal "rice", parsed[:item]
    assert_equal "cup", parsed[:unit]
    assert_equal "- 1 cup of rice", parsed[:raw], "the line is always kept exactly as typed"
  end

  test "meaningful adjectives survive into the match key" do
    assert_equal "ground beef", Recipes::Parse.line_attributes("500 g ground beef")[:item_key]
    assert_equal "onion", Recipes::Parse.line_attributes("1 large red onion")[:item_key].split.last
  end

  test "blank lines are skipped and positions are dense" do
    lines = Recipes::Parse.lines("1 onion\n\n\n2 carrots\n")

    assert_equal [ 0, 1 ], lines.map { |line| line[:position] }
  end

  test "component dividers are headings, not pseudo-ingredients" do
    [ "For the sauce:", "For the topping", "Topping:", "FOR THE DOUGH" ].each do |line|
      parsed = Recipes::Parse.line_attributes(line)
      assert parsed[:heading], line
      assert_equal "", parsed[:item_key], "a divider must carry no match key #{line.inspect}"
      assert_nil parsed[:quantity], line
    end
  end

  test "an ingredient that merely ends in a colon is still an ingredient" do
    parsed = Recipes::Parse.line_attributes("2 onions, chopped:")

    assert_not parsed[:heading]
    assert_in_delta 2.0, parsed[:quantity]
  end

  test "the divider keeps its text without the colon" do
    assert_equal "For the sauce", Recipes::Parse.line_attributes("For the sauce:")[:item]
  end

  test "quantities format back into kitchen fractions" do
    assert_equal "1½", Recipes::Quantity.format(1.5)
    assert_equal "¾", Recipes::Quantity.format(0.75)
    assert_equal "2", Recipes::Quantity.format(2.0)
    assert_equal "0.4", Recipes::Quantity.format(0.4), "no lie about being a nice fraction"
  end

  private
    def assert_parses(line, **expected)
      parsed = Recipes::Parse.line_attributes(line)
      expected.each { |key, value| assert_equal value, parsed[key].then { |v| v.is_a?(Float) ? v.round(3) : v }, key }
    end
end
