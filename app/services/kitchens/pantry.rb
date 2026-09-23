module Kitchens
  # Putting things in the kitchen: typed lines on a fridge tab, and lines
  # checked off the list (put away). Adding what's already there doesn't
  # make a second row — it's already there — though a new amount replaces
  # the old note.
  class Pantry
    MAX_LINES = 100

    def initialize(kitchen, by:)
      @kitchen = kitchen
      @by = by
    end

    # Typed or pasted lines onto one location. Returns the rows touched.
    def add_lines(text, location:)
      parsed = Recipes::Parse.lines(text).reject { |row| row[:heading] }.first(MAX_LINES)
      foods = Foods::Catalog.new(@kitchen).foods_by_key(parsed.map { |row| row[:item_key] })
      touched = parsed.map do |row|
        put(item: row[:item], item_key: row[:item_key], food: foods[row[:item_key]],
          quantity_note: note_for(row), location: location)
      end
      finish(touched)
    end

    # A checked-off list line, into wherever its food lives.
    def put_away(line)
      location = line.food&.default_location || "pantry"
      note = line.amount
      finish([ put(item: line.item, item_key: line.item_key, food: line.food, quantity_note: note,
        location: location, shopping_list_item: line) ]).first
    end

    private
      def put(item:, item_key:, food:, quantity_note:, location:, shopping_list_item: nil)
        existing = match(item_key, food, location)
        if existing
          existing.update!(quantity_note: quantity_note) if quantity_note.present?
          existing
        else
          @kitchen.pantry_items.create!(item: item.to_s.truncate(200), item_key: item_key, food: food,
            quantity_note: quantity_note&.truncate(100), location: location, added_by: @by,
            shopping_list_item: shopping_list_item)
        end
      end

      def match(item_key, food, location)
        scope = @kitchen.pantry_items.in_location(location)
        (food && scope.find_by(food: food)) || scope.find_by(item_key: item_key)
      end

      def note_for(row)
        [ Recipes::Quantity.with_unit(row[:quantity], row[:unit]), row[:note] ].compact.join(", ").presence
      end

      def finish(touched)
        if touched.any?
          @kitchen.broadcast_change
          ResolveFoodsJob.enqueue(@kitchen) if touched.any? { |row| row.food_id.nil? }
        end
        touched
      end
  end
end
