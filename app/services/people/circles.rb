module People
  # The circles grid (D-people-circles): one card per collection of people —
  # the circle first, then every group lens — so the two things that are the
  # same idea stop being drawn in two visual languages.
  #
  # The circle is deliberately *not* a Section. Sections are household-shared
  # taxonomy; `keep_in_touch` is per-user intent (D-people-dashboard), and
  # promoting it to a lens would quietly share your circle with your spouse
  # — the hidden default D9 forbids. So the two unify here, at the
  # presentation layer, and nowhere deeper: one Card the partial reads
  # without ever asking which kind it got.
  class Circles
    include Rails.application.routes.url_helpers

    # Faces on a card, before the +N bubble takes over.
    FACES = 5
    # Whose birthday is close enough to be the card's one line of signal.
    BIRTHDAY_WINDOW = 30

    Card = Struct.new(:section, :name, :path, :members, :member_count, :signal, :private, keyword_init: true) do
      def circle? = section.nil?
      def empty? = member_count.zero?
      def dom_id = circle? ? "circle" : "group-#{section.id}"
    end

    def self.for(viewer, section) = new(viewer, section).cards

    def initialize(viewer, section)
      @viewer = viewer
      @section = section
    end

    attr_reader :viewer, :section

    def cards = [ circle_card, *group_cards ]

    private
      # Pet lenses are children of People too (D-pet-primitive) — but a pet
      # is not a group of people, and her card is drawn by the pets strip.
      def groups
        @groups ||= begin
          owned = Section.owned_lens_ids
          section.children.reject { |child| owned.include?(child.id) }
        end
      end

      def circle_card
        people = viewer.people.circle.stalest_first.preload(:linked_user).with_attached_avatar.to_a

        Card.new(
          section: nil,
          name: "Your circle",
          # The full circle lives in the Address Book, filtered — cheaper
          # than a fourth People surface, and roster views belong there.
          path: people_path(circle: "1"),
          members: people,
          member_count: people.size,
          signal: circle_signal(people),
          private: true
        )
      end

      def group_cards
        members = members_by_section
        summaries = Sections::Summary.for(viewer, groups).index_by { |row| row.section.id }

        groups.map do |group|
          people = members.fetch(group.id, [])
          Card.new(
            section: group,
            name: group.name,
            path: section_path(group.slug),
            members: people,
            member_count: people.size,
            signal: group_signal(people, summaries[group.id]),
            private: false
          )
        end
      end

      # One query for every group's members rather than one per card — this
      # is the grid that silently degrades the day a CardDAV sync lands.
      # `visible_to`, not `viewer.people`: a group is a shared lens and may
      # hold a household member's own contact.
      def members_by_section
        return {} if groups.empty?

        Person.visible_to(viewer)
          .joins(:section_taggings)
          .where(section_taggings: { section_id: groups.map(&:id) })
          .select("people.*", "section_taggings.section_id AS grouped_section_id")
          .order(:name)
          .preload(:linked_user)
          .with_attached_avatar
          .group_by(&:grouped_section_id)
      end

      def circle_signal(people)
        return "No one yet — pick the relationships you're tending" if people.empty?

        # Same window the stay-in-touch watcher uses, so the card and the
        # nudge can never disagree about who has drifted. Never-logged
        # people aren't drifting — no signal, no claim (Q8).
        drifted = people.count { |person| person.last_contacted_on && person.last_contacted_on <= Watcher::StayInTouch::QUIET_AFTER.ago.to_date }
        unlogged = people.count { |person| person.last_contacted_on.nil? }

        [ pluralize(people.size, "person"),
          if drifted.positive?
            "#{drifted} you haven't talked to in a while"
          elsif unlogged.positive?
            "#{unlogged} with no contact logged yet"
          end ].compact.join(" · ")
      end

      def group_signal(people, summary)
        return "No one here yet" if people.empty?

        [ pluralize(people.size, "person"), next_thing(people, summary) ].compact.join(" · ")
      end

      # The single most useful fact, in the Sections::Summary spirit: what's
      # on the calendar, else whose birthday is close, else what's in
      # flight, else an honest invitation.
      def next_thing(people, summary)
        if summary&.next_event
          "#{summary.next_event.title} · #{summary.next_event.starts_at.strftime("%b %-d")}"
        elsif (birthday = next_birthday(people))
          "#{birthday.name}'s birthday #{birthday.next_birthday.strftime("%b %-d")}"
        elsif summary && !summary.quiet?
          in_flight = []
          in_flight << pluralize(summary.open_tasks_count, "open task") if summary.open_tasks_count.positive?
          in_flight << pluralize(summary.active_goals_count, "project") if summary.active_goals_count.positive?
          in_flight.join(" · ")
        else
          "nothing planned yet"
        end
      end

      def next_birthday(people)
        people.select(&:birthday)
          .select { |person| person.next_birthday <= Date.current + BIRTHDAY_WINDOW }
          .min_by(&:next_birthday)
      end

      def pluralize(count, noun) = "#{count} #{count == 1 ? noun : noun.pluralize}"
  end
end
