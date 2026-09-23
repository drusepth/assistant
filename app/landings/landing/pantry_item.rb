module Landing
  # Something to put in the kitchen (docs/FOOD_PLAN.md §5): a line off a
  # grocery receipt, or a label in a photo of a shelf. It lands in the
  # viewer's current kitchen through the same door as a typed line, so it
  # merges with what's already there and gets filed onto a food the same way.
  class PantryItem < Base
    self.description = "a food or grocery bought or on hand, to keep track of in the kitchen"
    self.produces = "pantry_items"

    field :item, "the food, in plain words (\"whole milk\", not a receipt code)", required: true
    field :quantity_note, "how much, as printed (\"2 l\", \"500 g\", \"6\")"
    field :location, "where it's kept", type: :choice, choices: Food::LOCATIONS.map { |value, label| [ label, value ] }
    field :expires_on, "a use-by or best-before date, only if printed", type: :date

    def self.label = "kitchen"

    def land!(attributes, sections:)
      kitchen = Kitchens::Current.for(user)
      Kitchens::Pantry.new(kitchen, by: user).put_one(
        item: attributes["item"], quantity_note: attributes["quantity_note"],
        location: attributes["location"].presence || "pantry",
        expires_on: parsed_date(attributes["expires_on"])
      )
    end

    def duplicate_of(attributes)
      kitchen = Kitchen.visible_to(user).find_by(id: user.current_kitchen_id) || Kitchen.visible_to(user).first
      return nil unless kitchen

      key = Recipes::Parse.key_for(attributes["item"])
      kitchen.pantry_items.find_by(item_key: key)
    end

    def preview(attributes)
      detail = [ attributes["quantity_note"], attributes["location"] && Food::LOCATIONS[attributes["location"]] ].compact_blank.join(" · ")
      Preview.new(kind: kind, title: attributes["item"].to_s, detail: detail.presence, date: attributes["expires_on"])
    end

    def default_sections = Section.where(slug: "food").to_a

    private
      def key_fields = %w[ item ]
  end
end
