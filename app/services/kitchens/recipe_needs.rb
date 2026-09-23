module Kitchens
  # What a recipe asks the shop for, scaled to the servings on screen: its
  # buyable, non-optional lines as list rows. The one place "a recipe onto a
  # list" is decided, shared by the recipe page's button and the week's plan.
  class RecipeNeeds
    def initialize(recipe, factor: 1.0)
      @recipe = recipe
      @factor = factor.to_r
    end

    def rows
      @recipe.recipe_ingredients.shoppable.where(optional: false).order(:position).map do |ingredient|
        { item: ingredient.item, item_key: ingredient.item_key, unit: ingredient.unit,
          quantity: ingredient.quantity && (ingredient.quantity * @factor).round(3) }
      end
    end
  end
end
