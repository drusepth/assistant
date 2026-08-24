module Tool
  # The calmer sibling of the lost-my-job Situation (docs/CAREER.md §3.8),
  # for the still-employed-but-leaving: one line of intent becomes a paced
  # search plan. Deliberately boring machinery — the value is cadence and
  # not dropping threads across the weeks a search actually takes.
  class PlanJobSearch < Base
    self.title = "Plan my job search"
    self.description = "A paced search — profile first, resume second, then a steady application cadence."
    self.section_slugs = %w[ career ]
    self.kind = :plan

    input :target, required: true,
      label: "What are you looking for?",
      hint: "“Out of retail management”, “first dev job”, “anything closer to home”."
    input :constraints,
      label: "Your constraints",
      hint: "Optional — “can't take a pay cut”, “needs to work around school pickup”."

    BRIEF = <<~BRIEF.freeze
      This goal is a job search by someone still employed (or between roles
      without the emergency framing) — pace beats panic. Structure the steps:
      - Foundation first (career): get the record straight before anything is
        sent — the work-history note and win log updated, then the resume
        refreshed from them. The app can tailor applications and prep
        interviews from this record, so the record is the investment.
      - Then targeting: a short list of realistic target roles or employers
        that fit the stated constraints, revisited weekly — not a scattershot.
      - Then cadence (the bulk of the steps): a sustainable weekly rhythm — a
        few quality applications a week, EACH tracked as its own task named
        for the employer, with a follow-up step a week or so after each; keep
        applying while waiting, and one weekly review step to prune and adjust.
      - Keep the current job intact: discretion steps where relevant
        (references who won't leak, interviews scheduled around work).
      Every step day-sized; spread the cadence steps over the coming weeks
      rather than piling them into day one.
    BRIEF

    def call
      plan_goal!(title: "Job search: #{inputs[:target].to_s.strip}", brief: BRIEF, description: description_text)
    end

    private
      def description_text
        [ user.work_summary&.then { |work| "Searching from: #{work}" },
          inputs[:constraints].presence ].compact.join("\n").presence
      end
  end
end
