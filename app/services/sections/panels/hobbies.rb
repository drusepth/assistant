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
      def cards
        @cards ||= begin
          rivers = ::Hobbies::Rivers.for(viewer, lenses).index_by { |row| row.section.id }
          Sections::Summary.for(viewer, lenses).map do |summary|
            Card.new(summary: summary, river: rivers.fetch(summary.section.id))
          end
        end
      end

      def feeds = @feeds ||= viewer.feeds.active.to_a

      def unread_count = @unread_count ||= cards.sum { |card| card.river.unread_count }

      Card = Struct.new(:summary, :river, keyword_init: true) do
        def section = summary.section
        def catch_all? = river.catch_all?
      end
    end
  end
end
