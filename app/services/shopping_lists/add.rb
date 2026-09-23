module ShoppingLists
  # Lines onto a list, merged with what's already there (docs/FOOD_PLAN.md
  # §3). "2 onions" onto a list holding "1 onion" makes "3 onions"; a line
  # the list already carries with no amount to add is simply already there.
  # Merging is arithmetic on the parser's own output — same item, same
  # canonical unit — and anything that doesn't add up cleanly (grams onto
  # cups) stays a second line rather than a converted guess
  # (Q-recipe-scale-units).
  #
  # Which lines count as "the same item" is the one judgment in here, and
  # it is exact: the parser's normalized key, i.e. the same words typed.
  # The food catalog (D-food-catalog) replaces that with a model-filed food
  # the day it lands; until then, "scallions" and "spring onions" are two
  # lines, which is a miss and never a wrong merge.
  class Add
    MAX_LINES = 100

    def initialize(list, by:)
      @list = list
      @by = by
    end

    # Returns the rows added or merged into.
    def lines(text, recipe: nil)
      parsed = Recipes::Parse.lines(text).reject { |row| row[:heading] }.first(MAX_LINES)
      rows(parsed.map { |row| row.slice(:item, :item_key, :quantity, :unit, :note) }, recipe: recipe)
    end

    # Already-structured rows (a recipe's own ingredients, scaled).
    def rows(rows, recipe: nil)
      touched = rows.filter_map { |attributes| add(attributes, recipe: recipe) }
      @list.kitchen.broadcast_change if touched.any?
      touched
    end

    private
      def add(attributes, recipe:)
        return if attributes[:item].blank? || attributes[:item_key].blank?

        existing = match_for(attributes)
        return merge(existing, attributes) if existing

        @list.items.create!(
          attributes.slice(:item, :item_key, :quantity, :unit).merge(
            note: attributes[:note].to_s.truncate(200).presence,
            recipe: recipe, added_by: @by
          )
        )
      end

      def match_for(attributes)
        @list.items.open.where(item_key: attributes[:item_key]).detect do |item|
          item.unit == attributes[:unit] || item.quantity.nil? || attributes[:quantity].nil?
        end
      end

      def merge(item, attributes)
        if item.quantity && attributes[:quantity] && item.unit == attributes[:unit]
          # "1 onion" + "2 onions": the wording typed for a plural amount
          # reads right for the total. No inflection rules — just the
          # person's own words.
          wording = attributes[:quantity] > 1 ? attributes[:item] : item.item
          item.update!(quantity: item.quantity + attributes[:quantity], item: wording)
        elsif item.quantity.nil? && attributes[:quantity]
          item.update!(quantity: attributes[:quantity], unit: attributes[:unit])
        end
        item
      end
  end
end
