module Foods
  # A kitchen's food catalog, as the rest of the Food section uses it
  # (D-food-catalog): which food a wording is, and filing the wordings that
  # aren't anything yet.
  #
  # Filing asks the model — batched, a key at most once per kitchen, ever —
  # when the household has one. Without one, every new wording becomes a food
  # of its own, so matching is the same words typed: it misses "scallions"
  # against "spring onions", and never merges two things that differ. The
  # catalog page says so, and a merge there is the household's own rule.
  class Catalog
    BATCH = 40
    MAX_PER_RUN = 160

    def initialize(kitchen)
      @kitchen = kitchen
    end

    def profile
      return @profile if defined?(@profile)

      candidate = @kitchen.user.household.model_profile
      @profile = candidate if candidate&.configured?
    end

    def model? = profile.present?

    # key => Food for the keys that have one.
    def foods_by_key(keys)
      @kitchen.food_aliases.where(key: keys.uniq).includes(:food).to_h { |entry| [ entry.key, entry.food ] }
    end

    # Recipes whose ingredients this kitchen should know: any a cook here
    # can see, since any of them might be cooked here.
    def recipe_ids
      @recipe_ids ||= @kitchen.cooks.flat_map { |cook| Recipe.visible_to(cook).pluck(:id) }.uniq
    end

    # Wordings nothing has filed yet: key => a wording to show the model.
    def unresolved(limit: MAX_PER_RUN)
      known = @kitchen.food_aliases.select(:key)
      found = {}
      sources.each do |scope|
        break if found.size >= limit

        scope.where.not(item_key: known).where.not(item_key: [ nil, "" ])
          .distinct.limit(limit).pluck(:item_key, :item)
          .each { |key, wording| found[key] ||= wording }
      end
      found.first(limit).to_h
    end

    def unresolved? = unresolved(limit: 1).any?

    # Files what's unfiled, then points rows at their foods. Returns the
    # number of new wordings filed.
    def resolve!
      entries = unresolved.to_a
      entries.each_slice(BATCH) { |batch| model? ? file_with_model(batch) : file_exactly(batch) }
      backfill!
      entries.size
    end

    # Rows written before their wording was filed (or re-filed by a merge)
    # pick up their food.
    def backfill!
      @kitchen.pantry_items
        .joins("INNER JOIN food_aliases ON food_aliases.kitchen_id = #{@kitchen.id} AND food_aliases.key = pantry_items.item_key")
        .where("pantry_items.food_id IS NULL OR pantry_items.food_id != food_aliases.food_id")
        .pluck("pantry_items.id", "food_aliases.food_id")
        .each { |id, food_id| PantryItem.where(id: id).update_all(food_id: food_id) }

      ShoppingListItem.joins(:shopping_list)
        .where(shopping_lists: { kitchen_id: @kitchen.id })
        .joins("INNER JOIN food_aliases ON food_aliases.kitchen_id = #{@kitchen.id} AND food_aliases.key = shopping_list_items.item_key")
        .where("shopping_list_items.food_id IS NULL OR shopping_list_items.food_id != food_aliases.food_id")
        .pluck("shopping_list_items.id", "food_aliases.food_id")
        .each { |id, food_id| ShoppingListItem.where(id: id).update_all(food_id: food_id) }
    end

    # One food for a wording, filing it on the spot when it's new — what an
    # interactive add does when the household has no model to wait for.
    def food_for!(key, wording)
      foods_by_key([ key ])[key] || file_exactly([ [ key, wording ] ]).first
    end

    # The foods this viewer may see listed (D-food-catalog): reached through
    # a row of this kitchen — which every cook can see — or through a recipe
    # the viewer can see. A food only someone else's private recipe mentions
    # is not on the page, even though it's in the kitchen's catalog.
    def visible_foods(viewer)
      recipe_keys = RecipeIngredient.shoppable.where(recipe_id: Recipe.visible_to(viewer).select(:id)).select(:item_key)
      via_recipes = @kitchen.food_aliases.where(key: recipe_keys).select(:food_id)
      via_rows = kitchen_row_scopes.map { |scope| @kitchen.food_aliases.where(key: scope.select(:item_key)).select(:food_id) }

      ([ via_recipes ] + via_rows).reduce(@kitchen.foods.none) { |foods, ids| foods.or(@kitchen.foods.where(id: ids)) }
    end

    private
      # The kitchen's own rows, by wording.
      def kitchen_row_scopes
        [ ShoppingListItem.joins(:shopping_list).where(shopping_lists: { kitchen_id: @kitchen.id }), @kitchen.pantry_items ]
      end

      def sources
        [
          ShoppingListItem.joins(:shopping_list).where(shopping_lists: { kitchen_id: @kitchen.id }),
          RecipeIngredient.shoppable.where(recipe_id: recipe_ids)
        ] + extra_sources
      end

      def extra_sources = [ @kitchen.pantry_items ]

      def file_exactly(batch)
        batch.map do |key, _wording|
          existing_food(key) || alias!(key, @kitchen.foods.create!(name: key.to_s.truncate(100)))
        end
      end

      def existing_food(key) = @kitchen.food_aliases.find_by(key: key)&.food

      # Two runs can reach the same new wording at once (an add and the
      # sweep); the unique index decides, and the loser uses the winner's.
      def alias!(key, food)
        @kitchen.food_aliases.create!(food: food, key: key)
        food
      rescue ActiveRecord::RecordNotUnique
        food.destroy if food.aliases.none? && food.filed_at.nil? && food.shopping_list_items.none?
        existing_food(key)
      end

      def file_with_model(batch)
        decisions = Classify.new(@kitchen, batch, profile: profile).call
        filed = {}
        decisions.each do |decision|
          food = decision.food || filed[decision.same_as_key] || create_from(decision)
          filed[decision.key] = existing_food(decision.key) || alias!(decision.key, food)
        end
      end

      # A model-proposed name that is already a food here is that food —
      # the model saying "new" about a name we already have is a match.
      def create_from(decision)
        existing = @kitchen.foods.where("lower(name) = ?", decision.name.downcase).first
        return existing if existing

        @kitchen.foods.create!(name: decision.name, aisle: decision.aisle, default_location: decision.location,
          kind_of: decision.kind_of, allergens: decision.allergens, filed_at: Time.current)
      end
  end
end
