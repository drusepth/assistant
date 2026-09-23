module Sections
  module Panels
    # The People lead panel (D-people-dashboard, docs/PEOPLE.md): the social dashboard
    # over the kept-in-touch circle — capture, Coming up, the circles grid,
    # reach-out — while the roster stays in the Address Book. The circle is
    # personal (own people, never visible_to): the flag is the owner's
    # intent, and you don't tend your spouse's circle.
    class People < Panel
      # How many of the circle get rows under the grid. The point of the
      # list is the one-tap loop, not the roster — the whole circle is one
      # tap away on its own card.
      REACH_OUT = 5

      # The panel's reach-out rows carry Reconnect prefilled, but the
      # Act-zone cards stay: with an empty circle the cards are the tools'
      # only front door.
      def hidden_browse = %i[ events people ]

      # The page leads with people, so "Nothing in People yet" under a
      # circle card with faces on it read as broken. The capture and the
      # cards are the way in.
      def show_empty_browse? = false

      # The three tools the page is about; the other seven fold away.
      LEAD_TOOLS = %w[ reconnect gift_ideas get_together ].freeze
      def lead_tool_slugs = LEAD_TOOLS

      # The circle and every group as one uniform card (D-people-circles).
      def circle_cards = @circle_cards ||= ::People::Circles.for(viewer, section)

      def circle_card = circle_cards.first

      # Everything below reads off the circle card rather than re-querying:
      # it already loaded the circle stalest-first with avatars attached.
      def circle_size = circle_card.member_count

      def reach_out = circle_card.members.first(REACH_OUT)

      def upcoming_birthdays
        @upcoming_birthdays ||= viewer.people.circle.birthday_within(30)
      end

      def address_book_size
        @address_book_size ||= Person.visible_to(viewer).count
      end

      # Give time (D-event-radar §4.6): volunteer openings and shifts near
      # the user's places that were judged to be a cause of theirs, on the
      # section whose whole premise is showing up. A blank causes brief and
      # no matched rows is zero pixels — not an empty card asking.
      def openings
        @openings ||= viewer.places.exists? ? ::Radar::River.new(viewer, matched: true).items(20).select { |row|
          row.kind_opening? || row.matches.any?(&:causes?)
        }.first(::Radar::River::PREVIEW) : []
      end
    end
  end
end
