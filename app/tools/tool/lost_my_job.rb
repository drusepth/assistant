module Tool
  # The second Situation (D7, docs/CAREER.md §3.7): the widest-blast-radius
  # career moment, hitting Career, Money, Benefits, and Health at once — and
  # the one where the user is least able to think in checklists. One plan
  # tool with a rich cross-section brief; structure as an antidote to panic.
  class LostMyJob < Base
    self.title = "I lost my job"
    self.description = "The first two weeks, structured: unemployment, insurance, bills, and the search — one plan."
    self.section_slugs = %w[ career money benefits health ]
    self.kind = :plan

    input :last_day, required: true,
      label: "When is (or was) your last day?",
      hint: "“Last Friday”, “end of the month”."
    input :details, kind: :textarea,
      label: "Anything else going on?",
      hint: "Optional — severance offered, family on your insurance, savings runway, how it ended."

    BRIEF = <<~BRIEF.freeze
      This goal is recovering from a job loss — a Situation that spans several
      life areas, so spread the steps' sections accordingly rather than filing
      everything in one place. Order matters: the deadline-bearing steps come
      first, the search itself second.
      - Benefits (benefits/money): file for unemployment THIS WEEK — eligibility
        starts from filing, not from the last day; gather the documents filing
        needs (ID, employment dates, final pay records). The app's benefits
        screener can check what else the household now qualifies for.
      - Health insurance (health/money): the coverage fork has a real deadline —
        compare continuing the employer plan (COBRA-style, [check the deadline
        in the exit paperwork, often 60 days]) against a marketplace plan where
        job loss opens a special enrollment window; pick by a dated step.
      - Severance and exit paperwork (career/rights): read before signing
        anything — the app can decode a severance agreement or any exit letter;
        note what was promised (final check, PTO payout, references).
      - Money triage (money): list the bills that flex (negotiable, pausable)
        and the ones that don't; the app has tools for negotiating bills and
        canceling subscriptions; set a weekly spending check while income is
        paused.
      - The story and the references (career/people): one honest paragraph
        about the exit for interviews, and the two or three people to line up
        as references.
      - The search (career): resume refreshed from the tracked record, then a
        sustainable application cadence — a few quality applications a week,
        each tracked as its own task, not a spray.
      Schedule the deadline-bearing steps in the first days; keep every step
      day-sized. Include only what fits this user's inputs — someone with
      severance and savings plans differently than someone without.
    BRIEF

    def call
      plan_goal!(title: "Get steady after the job loss", brief: BRIEF, description: description_text)
    end

    private
      def description_text
        [ "Last day: #{inputs[:last_day]}",
          user.work_summary&.then { |work| "The job that ended: #{work}" },
          inputs[:details].presence ].compact.join("\n")
      end
  end
end
