module Sections
  module Panels
    # The People lead panel (D38, docs/PEOPLE.md): the social dashboard
    # over the kept-in-touch circle — capture, Coming up, Your circle,
    # groups — while the roster stays in the Address Book. The circle is
    # personal (own people, never visible_to): the flag is the owner's
    # intent, and you don't tend your spouse's circle.
    class People < Panel
      # The panel's circle rows carry Reconnect and Gift ideas prefilled,
      # but their Act-zone cards stay: with an empty circle the cards are
      # the tools' only front door.
      def hidden_browse = %i[ events people ]

      def circle
        @circle ||= viewer.people.circle.stalest_first.includes(:sections)
      end

      def upcoming_birthdays
        @upcoming_birthdays ||= viewer.people.circle.birthday_within(30)
      end

      def circle_candidates
        @circle_candidates ||= viewer.people.where(keep_in_touch: false).order(:name)
      end

      def address_book_size
        @address_book_size ||= Person.visible_to(viewer).count
      end

      def groups = section.children
    end
  end
end
