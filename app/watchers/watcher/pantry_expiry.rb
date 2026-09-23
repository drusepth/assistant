module Watcher
  # Something in the kitchen goes off in the next two days, and a recipe you
  # can see uses it (docs/FOOD_PLAN.md §6). Deterministic: the dates are the
  # ones somebody typed, the "uses it" is the food catalog's join, and a
  # kitchen's items going off together make one nudge, not one each.
  #
  # Retires when those items are gone — used up, moved to the freezer (which
  # stops the clock), or re-dated.
  class PantryExpiry < Base
    self.section_slugs = %w[ food ]

    WITHIN = PantryItem::EXPIRING_WITHIN

    def scan
      Kitchen.visible_to(user).find_each do |kitchen|
        items = kitchen.pantry_items.where(expires_on: Date.current..(Date.current + WITHIN)).by_expiry.to_a
        next if items.empty?

        uses = recipes_using(kitchen, items)
        items = items.select { |item| uses[item.id].to_i.positive? }
        propose_for(kitchen, items, uses) if items.any?
      end
      proposals
    end

    def resolved?(suggestion)
      ids = suggestion.fingerprint[%r{items:([\d-]+)}, 1]&.split("-")&.map(&:to_i)
      return false if ids.nil?

      PantryItem.where(id: ids).where(expires_on: Date.current..).none?
    end

    private
      # item id => how many of the viewer's recipes use it.
      def recipes_using(kitchen, items)
        ideas = Kitchens::Ideas.new(kitchen, user, exclude: [])
        counts = Hash.new(0)
        ideas.candidates.each { |candidate| candidate.expiring.each { |item| counts[item.id] += 1 if items.include?(item) } }
        counts
      end

      def propose_for(kitchen, items, uses)
        first = items.first
        when_phrase = first.expires_on == Date.current ? "today" : first.expires_on.strftime("%A")
        count = uses[first.id]
        title = if items.one?
          "The #{first.item} goes off #{when_phrase} — #{count == 1 ? "a recipe uses" : "#{count} recipes use"} it"
        else
          "#{items.map(&:item).to_sentence.upcase_first} go off by #{items.last.expires_on.strftime("%A")}"
        end

        propose(
          fingerprint: "kitchen:#{kitchen.id}/#{Date.current.iso8601}/items:#{items.map(&:id).join("-")}",
          title: title,
          body: "What you can make with them is on the ideas page, the ones that use the most first.",
          action: { "path" => "/kitchens/#{kitchen.id}/ideas", "accept_label" => "What can I make?",
                    "expires_on" => items.last.expires_on.iso8601 }
        )
      end
  end
end
