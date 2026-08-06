module Tool
  # The first Situation (D7 → M2.4): a life event spanning sections,
  # shipped as nothing more than a plan tool with a rich cross-section
  # brief — which is the whole point. The Q7 pressure test rides here.
  class Moving < Base
    self.title = "Plan a move"
    self.description = "Everything a move touches — lease, deposits, utilities, addresses — as one plan."
    self.section_slugs = %w[ money renting people ]
    self.kind = :plan

    input :destination, required: true,
      label: "Where are you moving?",
      hint: "A city, a neighborhood, or just “a bigger place”."
    input :timing,
      label: "When?",
      hint: "Optional — “end of March”, “lease is up June 30”."
    input :details,
      label: "Anything else going on?",
      hint: "Optional — kids' school, pets, renting vs buying, job change…"

    BRIEF = <<~BRIEF.freeze
      This goal is a household move — a Situation that spans several life areas,
      so spread the steps' sections accordingly rather than filing everything in
      one place:
      - Current home (renting/money): required notice to the landlord per the
        lease, documenting condition for deposit recovery, final utility reads.
      - New home (money): deposits and upfront costs, setting up utilities and
        internet, renter's insurance.
      - Logistics: movers or truck, packing in stages, essentials box.
      - Address changes (money/people/rights): mail forwarding, bank and
        employer, subscriptions, voter registration, ID/license.
      - People and records (people/health/education): tell the people who matter,
        transfer medical and school records where relevant.
      Schedule steps backward from the move date when one is given — notice
      deadlines first, packing last. Include only what fits this user's inputs;
      a move across town needs less than a move across the country.
    BRIEF

    def call
      plan_goal!(title: "Move to #{inputs[:destination].to_s.strip}", brief: BRIEF, description: description_text)
    end

    private
      def description_text
        [ inputs[:timing].presence && "Timing: #{inputs[:timing]}",
          inputs[:details].presence ].compact.join("\n").presence
      end
  end
end
