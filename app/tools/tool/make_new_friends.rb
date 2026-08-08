module Tool
  # The widest loneliness funnel (docs/PEOPLE.md §4): adult friendship is a
  # skill nobody teaches. The brief pushes the evidence-shaped path —
  # recurring venues over one-off events, showing up repeatedly, following
  # up — and leans on the user's hobby lenses when they exist. Registered on
  # People and Hobbies both: the same funnel as find-your-people, seen from
  # the other end.
  class MakeNewFriends < Base
    self.title = "Make new friends"
    self.description = "A concrete plan for meeting people — recurring places, showing up, following up."
    self.section_slugs = %w[ people hobbies ]
    self.kind = :plan

    input :interests,
      label: "What do you like doing — or want to try?",
      hint: "Optional — the plan builds around it; blank works too."
    input :constraints,
      label: "Anything to work around?",
      hint: "Optional — evenings only, kids in tow, tight budget, new in town…"

    BRIEF = <<~BRIEF.freeze
      This goal is making new friends as an adult. Friendship grows from
      *repeated, unplanned* contact, so steer hard toward that and away from
      one-off events:
      - The core move is picking one or two *recurring* venues — a club, a
        class, volunteering, a league, a regular meetup — and committing to
        show up several times, not once. Build the plan around the user's
        stated interests where given.
      - Include a step for finding the venues (library boards, community
        centers, park district catalogs, local groups) — never invent
        specific local organizations or claim to know what exists nearby.
      - Include small talk-to-people steps with a concrete opener each, and a
        follow-up step: turning a familiar face into a plan ("we should grab
        coffee — does Tuesday work?").
      - Keep every step small and schedulable; showing up beats preparing to
        show up.
      File the steps under people (venue-finding may add hobbies).
    BRIEF

    def call
      plan_goal!(title: "Make new friends", brief: brief_text, description: description_text)
    end

    private
      def brief_text
        hobbies = Section.find_by(slug: "hobbies")&.children&.map(&:name) || []
        return BRIEF if hobbies.none?

        "#{BRIEF}\nThe user's existing hobbies — natural venues to build on: #{hobbies.join(", ")}."
      end

      def description_text
        [ inputs[:interests].presence && "Interests: #{inputs[:interests]}",
          inputs[:constraints].presence && "Working around: #{inputs[:constraints]}" ].compact.join("\n").presence
      end
  end
end
