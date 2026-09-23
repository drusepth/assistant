module Kitchens
  # What to cook, and what to buy (D-food-suggestions; docs/FOOD_PLAN.md §2).
  # Every answer here is arithmetic over rows the food catalog already
  # filed: which of a recipe's foods are in the kitchen, which are about to
  # go off, which one more purchase would complete the most dishes. The
  # model, when there is one, only picks among what this returns
  # (Kitchens::IdeasPick) — it never changes the ranking.
  #
  # Allergens only ever exclude. A recipe is left out when any of its foods
  # carries an allergen a diner listed; nothing here calls a dish safe.
  class Ideas
    READY = 0
    NEARLY = 2
    USE_SOON_DAYS = 3
    UNLOCK_PICKS = 3
    NO_DATE = Date.new(9999, 12, 31)

    Candidate = Data.define(:recipe, :have, :need, :expiring, :soonest, :allergens) do
      def missing = need.size
      def ready? = need.empty?
      def total = have.size + need.size
    end

    Unlock = Data.define(:name, :key, :food, :ready, :closer, :using_soon)

    def initialize(kitchen, viewer, exclude: nil)
      @kitchen = kitchen
      @viewer = viewer
      @exclude = exclude || kitchen.diners.flat_map(&:allergens).uniq
    end

    attr_reader :exclude

    def stock = @stock ||= Stock.new(@kitchen)

    # Recipes you have everything for, then missing one, then two — most
    # urgent pantry item first, then the one you've made least lately.
    def ready_to_make(limit: nil)
      # "Nearly" means most of it is in — a two-line recipe with nothing
      # in the kitchen isn't nearly anything.
      list = candidates.select { |candidate| candidate.ready? || (candidate.missing <= NEARLY && candidate.have.any?) }
        .sort_by { |candidate| [ candidate.missing, candidate.soonest || NO_DATE, cooked_order(candidate.recipe) ] }
      limit ? list.first(limit) : list
    end

    # Recipes that use what's about to go off, the most of it first.
    def use_it_up(limit: nil)
      list = candidates.select { |candidate| candidate.expiring.any? }
        .sort_by { |candidate| [ -candidate.expiring.size, candidate.missing, cooked_order(candidate.recipe) ] }
      limit ? list.first(limit) : list
    end

    # "What should I buy so the food we have gets used?" — a greedy set
    # cover. Each round scores every missing food by the recipes it would
    # move up a tier (to ready counts most, and more when the recipe uses
    # something going off), takes the best, treats it as bought, and goes
    # again.
    def buy_to_unlock(picks: UNLOCK_PICKS)
      needs = candidates.select { |candidate| candidate.missing.between?(1, NEARLY) }
        .map { |candidate| [ candidate, candidate.need.map { |line| identity(line) } ] }
      chosen = []

      picks.times do
        scores = Hash.new(0.0)
        needs.each do |candidate, missing|
          next if missing.empty?

          weight = missing.size == 1 ? 1.0 : 0.3
          weight += 0.5 if missing.size == 1 && candidate.expiring.any?
          missing.uniq.each { |id| scores[id] += weight }
        end
        best = scores.max_by { |id, score| [ score, -id.to_s.length ] }&.first
        break if best.nil?

        ready = needs.count { |_, missing| missing.uniq == [ best ] }
        closer = needs.count { |_, missing| missing.include?(best) } - ready
        using_soon = needs.count { |candidate, missing| missing.uniq == [ best ] && candidate.expiring.any? }
        needs = needs.map { |candidate, missing| [ candidate, missing - [ best ] ] }
        chosen << Unlock.new(name: names[best], key: best, food: foods_by_id[best], ready: ready, closer: closer, using_soon: using_soon)
      end
      chosen
    end

    def candidates
      @candidates ||= recipes.filter_map do |recipe|
        lines = recipe.recipe_ingredients.select { |line| !line.heading? && !line.optional? }
        next if lines.empty?

        foods = stock.foods_for(lines.map(&:item_key))
        allergens = lines.flat_map { |line| foods[line.item_key]&.allergens || [] }.uniq
        next if (allergens & @exclude).any?

        have, need = lines.partition { |line| stock.have?(line.item_key, foods[line.item_key]) }
        rows = have.flat_map { |line| stock.rows_for(line.item_key, foods[line.item_key]) }
        expiring = rows.select { |row| row.expires_on && row.expires_on <= Date.current + USE_SOON_DAYS }.uniq
        Candidate.new(recipe: recipe, have: have, need: need, expiring: expiring,
          soonest: expiring.filter_map(&:expires_on).min, allergens: allergens)
      end
    end

    private
      def recipes
        Recipe.visible_to(@viewer).includes(:recipe_ingredients).with_attached_image.to_a
      end

      # Least recently cooked first; never cooked before everything.
      def cooked_order(recipe) = recipe.last_cooked_on || Date.new(1970)

      # A missing line is its food when the catalog filed it, else its words.
      def identity(line)
        food = stock.foods_for([ line.item_key ])[line.item_key]
        key = food ? food.id : line.item_key
        names[key] ||= food&.name || line.item
        foods_by_id[key] = food if food
        key
      end

      def names = @names ||= {}
      def foods_by_id = @foods_by_id ||= {}
  end
end
