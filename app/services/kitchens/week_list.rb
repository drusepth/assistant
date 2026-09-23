module Kitchens
  # "Make the list for this week" (docs/FOOD_PLAN.md §4): every planned meal
  # from today on, its recipe's missing ingredients scaled to the meal's
  # servings, onto one list — each line saying which recipe it's for.
  #
  # Idempotent by meal: a meal whose ingredients already went on a list is
  # skipped until its recipe or servings change, so pressing the button
  # twice doesn't buy two lots of mince.
  class WeekList
    Result = Data.define(:meals, :lines)

    def initialize(kitchen, list, by:)
      @kitchen = kitchen
      @list = list
      @by = by
    end

    def call(range)
      meals = @kitchen.meals.between(range).where(date: Date.current..).where(listed_at: nil)
        .where.not(recipe_id: nil).includes(recipe: :recipe_ingredients).in_order.to_a
      add = ShoppingLists::Add.new(@list, by: @by)
      lines = meals.sum do |meal|
        factor = meal.recipe.scale_factor(meal.servings)
        added = add.rows(RecipeNeeds.new(meal.recipe, factor: factor, kitchen: @kitchen).rows, recipe: meal.recipe)
        meal.update_columns(listed_at: Time.current)
        added.size
      end
      Result.new(meals: meals.size, lines: lines)
    end
  end
end
