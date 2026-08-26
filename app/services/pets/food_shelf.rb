module Pets
  # The food shelf (D-pet-food-shelf): what she's on, when the bag runs out,
  # and what it costs a month. Everything here is arithmetic over rows the
  # owner typed — no model is called, and nothing is estimated that the
  # numbers can't actually say.
  class FoodShelf
    # A bag with a week left is a bag to reorder; a bag with three weeks isn't
    # news yet.
    REORDER_LEAD = 7.days

    def initialize(pet)
      @pet = pet
    end

    attr_reader :pet

    def current = @current ||= pet.pet_foods.current.to_a
    def past = @past ||= pet.pet_foods.past.to_a
    def any? = current.any? || past.any?

    # The whole diet's monthly cost, or nil when no food carries enough
    # numbers to say — an honest nil beats a total that silently means
    # "the two foods we could price".
    def monthly_cost_cents
      priced = current.filter_map(&:monthly_cost_cents)
      priced.any? ? priced.sum : nil
    end

    # True when some food is priced and some isn't, so the surface can say the
    # total is partial rather than let it read as the whole bill.
    def partial_cost? = current.any? { |food| food.monthly_cost_cents.nil? } && monthly_cost_cents.present?

    # Foods whose bag is out, or nearly. Soonest first — the reorder radar's
    # pull surface, and what the watcher proposes from.
    def running_out(on: Date.current)
      current.select { |food| food.runs_out_on && food.runs_out_on <= on + REORDER_LEAD }
        .sort_by(&:runs_out_on)
    end

    # The title the reorder event and task carry. Named here so the watcher,
    # the button and the deduplication all say the same words.
    def self.reorder_title(food) = "Reorder #{food.pet.name}'s #{food.display_name}"
  end
end
