module Watcher
  # The bag is nearly out (D-pet-food-shelf). Purely deterministic: the food
  # shelf already knows when a package runs out, because the owner typed the
  # bag size and the daily amount — no model, no guess, and nothing at all for
  # a food whose numbers can't say (a bag in cans fed in scoops, or one whose
  # opened date is blank).
  #
  # It stays quiet when the reorder is already on the calendar, which is the
  # difference between a useful nudge and being told twice about something
  # you handled.
  class PetFoodReorder < Base
    self.section_slugs = %w[ money health ]

    def scan
      user.pets.active.includes(:section, :pet_foods).each do |pet|
        Pets::FoodShelf.new(pet).running_out.each { |food| propose_reorder(pet, food) }
      end
      proposals
    end

    # The bag got handled: reordered onto the calendar, refilled (which
    # moves `runs_out_on`, so the fingerprint's date no longer describes
    # anything), or the food came off the shelf entirely.
    def resolved?(suggestion)
      _, food_id, runs_out_on = suggestion.fingerprint.split("/")
      return false if runs_out_on.blank?

      food = PetFood.where(pet: user.pets).find_by(id: food_id)
      return true if food.nil?

      already_on_the_calendar?(food) || food.runs_out_on&.iso8601 != runs_out_on
    end

    private
      def propose_reorder(pet, food)
        return if already_on_the_calendar?(food)

        propose(
          # By the date the bag runs out: the next bag is a new nudge, and a
          # dismissed one stays dismissed for this bag only.
          fingerprint: "#{food.id}/#{food.runs_out_on.iso8601}",
          title: Pets::FoodShelf.reorder_title(food),
          body: body_for(pet, food),
          action: { "task" => { "title" => Pets::FoodShelf.reorder_title(food), "due_on" => food.runs_out_on.iso8601 } },
          sections: [ "money", pet.section.slug ]
        )
      end

      def body_for(pet, food)
        days = (food.runs_out_on - Date.current).to_i
        when_phrase = if days.negative? then "ran out around #{food.runs_out_on.strftime("%B %-d")}"
        elsif days.zero? then "runs out today"
        else "runs out in about #{ActionController::Base.helpers.pluralize(days, "day")}"
        end

        "#{pet.name}'s #{food.display_name} #{when_phrase}, going by the bag size and what #{pet.pronouns.subject} #{pet.pronouns.verb("eats", "eat")}."
      end

      # The pull surface writes an Event with this exact title; the watcher
      # and the button therefore can't talk over each other.
      def already_on_the_calendar?(food)
        user.events.where(title: Pets::FoodShelf.reorder_title(food))
          .where(starts_at: Date.current.beginning_of_day..).exists?
      end
  end
end
