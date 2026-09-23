module Kitchens
  # What the kitchen has, for matching (D-food-suggestions): the foods in it
  # and, for lines the catalog hasn't filed yet, their exact wording.
  #
  # A recipe line is satisfied by its own food, or by a food that is a kind
  # of it — chicken thighs in the fridge count for a recipe's "chicken",
  # never the reverse. All of this is set arithmetic over rows the catalog
  # already filed; nothing here decides what anything is.
  class Stock
    def initialize(kitchen)
      @kitchen = kitchen
    end

    def items = @items ||= @kitchen.pantry_items.to_a

    def food_ids
      @food_ids ||= begin
        ids = items.filter_map(&:food_id).to_set
        general = Food.where(id: ids.to_a).where.not(kind_of_id: nil).pluck(:kind_of_id)
        ids.merge(general)
      end
    end

    def keys = @keys ||= items.map(&:item_key).to_set

    # key => food, for every recipe key the matcher is asked about.
    def foods_for(keys)
      @foods_for ||= {}
      missing = keys.uniq - @foods_for.keys
      if missing.any?
        found = Foods::Catalog.new(@kitchen).foods_by_key(missing)
        missing.each { |key| @foods_for[key] = found[key] }
      end
      @foods_for.slice(*keys)
    end

    def have?(key, food = foods_for([ key ])[key])
      food ? food_ids.include?(food.id) : keys.include?(key)
    end

    # The pantry rows that answer for a recipe line — what "Cooked it" offers
    # to take out.
    def rows_for(key, food = foods_for([ key ])[key])
      items.select do |row|
        if food
          row.food_id == food.id || (row.food && row.food.kind_of_id == food.id)
        else
          row.item_key == key
        end
      end
    end

    # A recipe's buyable, non-optional lines split into have / need.
    def split(recipe)
      lines = recipe.recipe_ingredients.select { |line| !line.heading? && !line.optional? }
      foods = foods_for(lines.map(&:item_key))
      lines.partition { |line| have?(line.item_key, foods[line.item_key]) }
    end
  end
end
