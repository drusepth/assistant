module Watcher
  # The last eight weeks of dinners are the same handful, and the box holds
  # recipes you saved and never made (docs/FOOD_PLAN.md §6; carried over from
  # RECIPES_PLAN §5). Read from the meal plan, which is the only record of
  # *how often* — the cook log keeps a count and a last date, not a rhythm.
  # At most once a month, and only for a kitchen that plans enough to tell.
  class RecipeRut < Base
    self.section_slugs = %w[ food ]

    WINDOW = 8.weeks
    MIN_MEALS = 10
    MAX_DISTINCT = 6
    OFFERED = 3

    def scan
      Kitchen.visible_to(user).find_each do |kitchen|
        recent = kitchen.meals.where(date: (Date.current - WINDOW)...Date.current).where.not(recipe_id: nil)
        next if recent.count < MIN_MEALS || recent.distinct.count(:recipe_id) > MAX_DISTINCT

        untried = Recipe.visible_to(user).where(times_cooked: 0).where.not(id: recent.select(:recipe_id))
          .order(:created_at).limit(OFFERED).to_a
        propose_for(kitchen, untried) if untried.any?
      end
      proposals
    end

    private
      def propose_for(kitchen, untried)
        propose(
          fingerprint: "kitchen:#{kitchen.id}/month:#{Date.current.strftime("%Y-%m")}",
          title: "The same few dinners lately — here's something you saved",
          body: "Saved and never made: #{untried.map(&:title).to_sentence}.",
          action: { "path" => "/recipes/#{untried.first.id}", "accept_label" => "Open #{untried.first.title.truncate(30)}",
                    "expires_on" => Date.current.end_of_month.iso8601 }
        )
      end
  end
end
