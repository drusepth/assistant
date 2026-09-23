module Watcher
  # A dinner planned in the next two days needs things that are neither in
  # the kitchen nor on a list (docs/FOOD_PLAN.md §6). The plan named a
  # "before the shop" watcher that read the calendar for the shopping trip;
  # deciding which event *is* the shop would be reading titles for meaning
  # (D-no-keyword-logic), so this watches the thing that matters instead —
  # the meal — and is arithmetic end to end.
  class MealNeeds < Base
    self.section_slugs = %w[ food ]

    AHEAD = 2

    def scan
      Kitchen.visible_to(user).find_each do |kitchen|
        kitchen.meals.between(Date.current..(Date.current + AHEAD)).where.not(recipe_id: nil)
          .includes(recipe: :recipe_ingredients).in_order.each do |meal|
          next unless meal.recipe.visible_to?(user)

          missing = missing_for(kitchen, meal)
          propose_for(kitchen, meal, missing) if missing.any?
        end
      end
      proposals
    end

    # Handled: bought, listed, or the meal moved or went.
    def resolved?(suggestion)
      meal = Meal.find_by(id: subject_id(suggestion, "meal"))
      return true if meal.nil? || meal.recipe.nil?

      meal.date.iso8601 != suggestion.fingerprint[%r{/(\d{4}-\d{2}-\d{2})\z}, 1] || missing_for(meal.kitchen, meal).empty?
    end

    private
      def missing_for(kitchen, meal)
        need = Kitchens::Stock.new(kitchen).split(meal.recipe).last
        return [] if need.empty?

        listed = ShoppingListItem.open.joins(:shopping_list).where(shopping_lists: { kitchen_id: kitchen.id })
        listed_keys = listed.pluck(:item_key).to_set
        listed_foods = listed.where.not(food_id: nil).pluck(:food_id).to_set
        foods = Foods::Catalog.new(kitchen).foods_by_key(need.map(&:item_key))
        need.reject { |line| listed_keys.include?(line.item_key) || listed_foods.include?(foods[line.item_key]&.id) }
      end

      def propose_for(kitchen, meal, missing)
        day = meal.date == Date.current ? "Tonight's" : "#{meal.date.strftime("%A")}'s"
        propose(
          fingerprint: "kitchen:#{kitchen.id}/meal:#{meal.id}/#{meal.date.iso8601}",
          title: "#{day} #{meal.title} needs #{missing.size == 1 ? missing.first.item : "#{missing.size} things"}",
          body: "Not in the kitchen and not on a list: #{missing.map(&:item).to_sentence}.",
          action: { "path" => "/recipes/#{meal.recipe_id}?servings=#{meal.servings || meal.recipe.servings}",
                    "accept_label" => "Open the recipe", "expires_on" => meal.date.iso8601 }
        )
      end
  end
end
