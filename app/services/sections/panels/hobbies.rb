module Sections
  module Panels
    # The Hobbies lead panel (D25/docs/HOBBIES.md, D-hobby-feeds): lens cards
    # with engagement signal *and* the hobby's own river, or the
    # what-do-you-do-for-fun capture before any lens exists.
    #
    # The reader used to sit under the grid as one shared card, which had it
    # backwards — the river is not a place you go, it is what makes each
    # hobby different every day. So it moves inside the cards, under the
    # engagement line rather than above it: a card whose top line is "next:
    # class Thursday" and whose bottom line is reading material has its
    # priorities visible in its layout (docs/HOBBIES_HUB_PLAN.md §6).
    class Hobbies < Panel
      def lenses = @lenses ||= ::Hobbies::OtherInterests.lenses(section)

      # Engagement signal and river for the same lens, zipped so the card
      # partial reads one object. Summaries are batched by Sections::Summary
      # and the rivers by Hobbies::Rivers; neither asks per card.
      def rows
        @rows ||= begin
          rivers = ::Hobbies::Rivers.for(viewer, lenses).index_by { |row| row.section.id }
          Sections::Summary.for(viewer, lenses).map do |summary|
            Card.new(summary: summary, river: rivers.fetch(summary.section.id))
          end
        end
      end

      # A card is what a hobby with something in it gets. A household names
      # hobbies faster than it fills them, so on a real instance most of them
      # have nothing to say — and a grid of eleven cards saying "nothing
      # planned yet" buries the three that do. Those become one line each in
      # `quiet_lenses` instead.
      #
      # "Something in it" is feeds or engagement, never *unread* — a card
      # that vanished the moment you finished reading it would make the grid
      # rearrange itself as you use it. For the same reason the order is
      # taxonomy order within the group, not unread count: a grid whose cards
      # trade places every morning is one nobody learns the shape of.
      def cards
        @cards ||= rows.select { |card| card.catch_all? ? card.river.any_feeds? : card.anything? }
      end

      # The hobbies that didn't earn a card: names and links, in one place.
      def quiet_lenses
        carded = cards.map { |card| card.section.id }.to_set
        @quiet_lenses ||= rows.map(&:section).reject { |lens| carded.include?(lens.id) }
      end

      def feeds = @feeds ||= viewer.feeds.active.to_a

      # What the capture offers (D-hobby-spotting): hobbies spotted in this
      # user's own reading first, then the broad starter names. The chips
      # are read here rather than computed in the view, because a hub tile
      # is a section feature and section features live in the panel (D37).
      def suggestions = @suggestions ||= ::Hobbies::Suggestions.for(viewer, section)

      # The stocked shelf, only while there is nothing to read at all
      # (D-hobby-feeds §7.1): a household with one feed has found the paste
      # field and doesn't need it.
      def starters = feeds.empty? ? ::Feeds::Starters.groups : nil

      def unread_count = @unread_count ||= rows.sum { |card| card.river.unread_count }

      Card = Struct.new(:summary, :river, keyword_init: true) do
        def section = summary.section
        def catch_all? = river.catch_all?
        # Sources or a life: either earns the space a card takes.
        def anything? = river.any_feeds? || !summary.quiet?

        # The card's one line of signal, and it rides *beside* the hobby's
        # name rather than under it. A line each for "Nothing planned yet —
        # dive back in" and "1 open task" cost every card a row of height to
        # say almost nothing; at hub altitude the useful part is the date or
        # the number, and the detail is one click away on the lens page.
        #
        # One thing, most actionable first: a date beats a count, because a
        # date is a commitment and a count is a pile.
        def meta
          return "no hobby yet" if catch_all?
          return summary.next_event.starts_at.strftime("%b %-d") if summary.next_event
          return pluralize(summary.open_tasks_count, "task") if summary.open_tasks_count.positive?
          return pluralize(summary.active_goals_count, "project") if summary.active_goals_count.positive?

          nil
        end

        # What the short version is short *for* — the hover title, so the
        # meaning of "Aug 29" is never more than a pointer away.
        def meta_title
          summary.next_event&.title
        end

        private
          def pluralize(count, noun) = ActionController::Base.helpers.pluralize(count, noun)
      end
    end
  end
end
