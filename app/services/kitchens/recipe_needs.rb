module Kitchens
  # What a recipe asks the shop for, scaled to the servings on screen: its
  # buyable, non-optional lines that the kitchen doesn't already have, as
  # list rows. The one place "a recipe onto a list" is decided, shared by
  # the recipe page's button and the week's plan.
  class RecipeNeeds
    def initialize(recipe, factor: 1.0, kitchen: nil)
      @recipe = recipe
      @factor = factor.to_r
      @kitchen = kitchen
    end

    def lines
      return Kitchens::Stock.new(@kitchen).split(@recipe).last if @kitchen

      @recipe.recipe_ingredients.select { |line| !line.heading? && !line.optional? }
    end

    def rows
      lines.sort_by(&:position).map do |ingredient|
        { item: ingredient.item, item_key: ingredient.item_key, unit: ingredient.unit,
          quantity: ingredient.quantity && (ingredient.quantity * @factor).round(3) }
      end
    end
  end
end
