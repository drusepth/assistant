module Tool
  # The first Situation (D7, M2.4) and the Q7 cross-section pressure test:
  # a move is not a project in one section, it's a life event that touches
  # Renting, Money, People, Health, and the calendar at once. As designed,
  # it's nothing but a plan tool with a richer brief — the entire
  # cross-section behavior rides the shared Goals::BreakDown pipeline and
  # per-step multi-tagging that already exist. If this brief produces a
  # well-tagged plan, the Situations thesis holds.
  class Moving < PlanBase
    self.title = "I'm moving"
    self.description = "Everything a move touches — notice, deposit, utilities, addresses, people — as one plan."
    self.section_slugs = %w[ renting money people ]

    input :details, required: true,
      label: "The basics",
      hint: "“Across town to a 2-bed, end of June”, “out of state in August for a new job”."
    input :wrinkles,
      label: "Anything tricky?",
      hint: "Optional — “breaking the lease early”, “kids changing schools”, “moving with a dog”."

    BRIEF = <<~BRIEF.freeze
      This goal is a moving plan — a life event that touches many parts of life
      at once, not a project in a single section. Cover whichever of these the
      user's situation implies, and skip what clearly doesn't apply:
      - The old place: give written notice by the lease's deadline; schedule the
        walkthrough; photograph the empty unit; put the forwarding address in
        writing so the security deposit can follow.
      - The new place: read the lease before signing; document move-in condition
        with photos on day one; sort renters insurance.
      - Money: estimate moving costs and any overlapping rent or double deposit
        month; update the budget once the dust settles.
      - Utilities and services: stop and start electricity and internet around
        the move date; settle final bills.
      - Address changes: postal forwarding; bank, employer, and insurance;
        subscriptions; driver's license or ID within the new state's window when
        the move crosses state lines; voter registration at the new address.
      - Health: transfer prescriptions and records when the move means new
        providers.
      - People: tell the people who matter; handle school transfers when kids
        are involved; line up moving-day help.
      Order the steps by real timeline pressure — written notice and anything
      else with a dated consequence first — and resolve dates against the move
      date when the user gives one.
      Tag every step with the sections it truly touches: a deposit letter is
      renting and money, a school transfer is people and education, a
      prescription transfer is health. This plan spans sections by nature —
      that is the point.
    BRIEF

    private
      def goal_title = "Moving — #{inputs[:details].to_s.strip.truncate(60)}"
      def goal_description = inputs[:wrinkles].presence
  end
end
