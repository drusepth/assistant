module Tool
  # Open enrollment's asymmetry problem: employers and insurers publish
  # dense plan documents, and choosing wrong costs real money. Two plan
  # documents from the vault, side by side — only the numbers the documents
  # actually state (anything else is a [PLACEHOLDER] naming what to look
  # up), then scenario reasoning tied to what the user said about their
  # household. Organization, not benefits advice — the disclaimer is
  # appended by code.
  class ComparePlans < Base
    self.title = "Compare health plans"
    self.description = "Two plan documents side by side — costs, coverage, and which fits your household."
    self.section_slugs = %w[ health ]
    self.kind = :draft

    input :plan_a_id, kind: :document, required: true, label: "First plan document"
    input :plan_b_id, kind: :document, required: true, label: "Second plan document"
    input :household,
      label: "Who's covered, and what care do you expect?",
      hint: "Optional — “family of four, one kid in braces, regular asthma meds”."

    # Two documents share the prompt, so each gets a smaller slice than the
    # usual single-document budget.
    MAX_PLAN_CHARS = 9_000

    DISCLAIMER = "A comparison can only weigh what these documents say — the plan documents " \
      "control, and this-year premiums and network details are worth confirming with the " \
      "insurer or your benefits contact before choosing. This organizes; it doesn't advise.".freeze

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the plan-comparison feature of a private, self-hosted life
      assistant. The user has two health-plan documents and needs to choose.
      The draft's body must, in short headed parts: summarize each plan in two
      or three plain-language sentences; compare, side by side, only the
      numbers and rules the documents themselves state — premiums, deductibles,
      copays, coinsurance, out-of-pocket maximums, network type, referral
      rules, drug coverage — writing a [BRACKETED PLACEHOLDER] naming what to
      look up wherever a document is silent, and never guessing; then reason
      through which plan wins in the scenarios that fit what the user said
      about their household ("if the year is mostly checkups...", "if someone
      hits the out-of-pocket max..."), sticking strictly to stated numbers;
      and end with the questions worth asking the insurer or benefits contact
      before deciding.
      #{DRAFT_FORMAT}
      follow_ups are small concrete actions ("confirm the pediatrician is
      in-network under plan A", "get this year's premium from HR").
    PROMPT

    private
      def messages
        [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user", content: user_prompt }
        ]
      end

      def user_prompt
        if plan_a.id == plan_b.id
          raise Llm::Error, "Those are the same document — pick two different plan documents to compare."
        end

        parts = [ "Today's date: #{Date.current.iso8601}" ]
        parts << "The user's household and expected care: #{inputs[:household]}" if inputs[:household].present?
        parts << "Plan A (titled “#{plan_a.title}”):\n#{document_text(plan_a).truncate(MAX_PLAN_CHARS)}"
        parts << "Plan B (titled “#{plan_b.title}”):\n#{document_text(plan_b).truncate(MAX_PLAN_CHARS)}"
        parts.join("\n\n")
      end

      def plan_a = chosen_document(:plan_a_id)
      def plan_b = chosen_document(:plan_b_id)

      def filing_sources = [ plan_a, plan_b ]

      def handle(response)
        body = response.dig("draft", "body")
        raise Llm::Error, "The model didn't return a comparison — try again." if body.blank?

        create_note(
          title: response.dig("draft", "title").presence || fallback_title,
          body: [ body, DISCLAIMER ].join("\n\n")
        )
        create_follow_ups(response["follow_ups"])
      end

      def fallback_title = "Compared — #{plan_a.title} vs. #{plan_b.title}"
  end
end
