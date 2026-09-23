module Recipes
  # After "Cooked it" (docs/FOOD_PLAN.md §3): the kitchen rows this recipe
  # drew on, offered as a checklist of what's gone. Offered, never assumed —
  # a recipe that takes a pinch of the paprika hasn't finished the jar, and
  # nothing here knows how much is left (Q-pantry-quantities).
  class UseUp
    def initialize(recipe, kitchen)
      @recipe = recipe
      @kitchen = kitchen
    end

    def rows
      @rows ||= begin
        stock = Kitchens::Stock.new(@kitchen)
        lines = @recipe.recipe_ingredients.reject(&:heading?)
        foods = stock.foods_for(lines.map(&:item_key))
        lines.flat_map { |line| stock.rows_for(line.item_key, foods[line.item_key]) }.uniq
      end
    end
  end
end
