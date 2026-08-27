module Hobbies
  # What the "Add another hobby" tile offers (D-hobby-spotting).
  #
  # Two kinds of chip, and the order is the whole argument:
  #
  #   1. **Spotted** — names `Hobbies::Spotter` read out of the feeds the
  #      user follows and the stories they actually opened. These are about
  #      this household; they lead.
  #   2. **Starters** — a short, broad, cheap-to-start list, the same for
  #      everybody. These are a prompt for somebody who has nothing spotted
  #      yet, and they fill whatever room is left.
  #
  # The list used to be starters only, in a fixed order, so the same four
  # names sat there forever no matter what the instance knew about its
  # user. Anything already named as a hobby drops out of both kinds; so
  # does a spotted name whose nudge the user dismissed this month, because
  # saying "no" once should say it to every surface.
  #
  # It lives here rather than in SectionsHelper on purpose (D37): section
  # features go in the section's own files, and that helper is one of the
  # three no branch may edit for one.
  module Suggestions
    STARTERS = [
      "Reading", "Cooking", "Baking", "Gardening", "Drawing", "Photography",
      "Gaming", "Board games", "Hiking", "Running", "Guitar", "Knitting",
      "Woodworking", "Writing"
    ].freeze

    # `reason` is what a spotted chip knows and a starter doesn't: why this
    # name is here. It rides the chip as its hover title — the chip itself
    # stays one word, because a row of explanations is not a row of chips.
    Chip = Struct.new(:name, :reason, keyword_init: true) do
      def spotted? = reason.present?
    end

    module_function

    def for(user, hobbies_section, limit: nil)
      taken = taken_names(hobbies_section)
      chips = spotted(user, taken) + starters(taken)
      limit ? chips.first(limit) : chips
    end

    def taken_names(hobbies_section)
      hobbies_section.children.map { |child| child.name.downcase }.to_set
    end

    def spotted(user, taken)
      user.spotted_hobbies.ordered.filter_map do |row|
        next if taken.include?(row.name.downcase)
        next if quieted?(user, row.name)

        Chip.new(name: row.name, reason: row.reason)
      end
    end

    def starters(taken)
      STARTERS.reject { |name| taken.include?(name.downcase) }.map { |name| Chip.new(name: name) }
    end

    # Dismissed or snoozed this month, as the nudge — one refusal, both
    # surfaces.
    def quieted?(user, name)
      user.suggestions.where.not(status: :pending)
        .exists?(fingerprint: ::Watcher::HobbyFromFeeds.fingerprint_for(name))
    end
  end
end
