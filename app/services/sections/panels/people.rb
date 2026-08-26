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

      def circle_candidates
        @circle_candidates ||= viewer.people.where(keep_in_touch: false).order(:name)
      end

      # Who a group card can add. Anyone the viewer can see (a group is a
      # shared lens), circle first — the picker-scaling rule from
      # docs/PEOPLE.md §3, since the address book is what gets long.
      def member_candidates
        @member_candidates ||= Person.visible_to(viewer).order(keep_in_touch: :desc, name: :asc)
      end

      def address_book_size
        @address_book_size ||= Person.visible_to(viewer).count
      end

      # Pets are members of the household (D-pet-primitive), so their cards
      # sit on this page rather than in a section of their own. Zero pets is
      # zero pixels — the partial draws nothing but the add tile.
      def pet_cards = @pet_cards ||= ::Pets::Cards.new(viewer)

      def pets = pet_cards.active_cards

      def remembered_pets = pet_cards.gone_cards
    end
  end
end
