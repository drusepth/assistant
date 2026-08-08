module Tool
  # Health insurance in plain language — the coverage half of Q3 (billing
  # disputes stay in Rights). The model explains what the user's own plan
  # document says: the numbers it actually states, each in words a
  # layperson can use, and how to act on them. It never invents a number —
  # what the document doesn't state becomes a [PLACEHOLDER] naming what to
  # look up. The not-coverage-advice disclaimer is appended by code, and
  # the D28 routing seam offers the natural next moves: find in-network
  # care with this plan, or appeal when the document turns out to be a
  # denial (with the document attached by code, never by the model).
  class InsuranceExplainer < Base
    self.title = "Understand my insurance"
    self.description = "Your plan in plain language — what you'd pay when, what's covered, and how to use it."
    self.section_slugs = %w[ health ]
    self.kind = :draft

    input :document_id, kind: :document, required: true,
      label: "Which plan document?",
      hint: "An insurance card, Summary of Benefits (SBC), EOB, or letter from your insurer."
    input :question,
      label: "Anything specific you're wondering?",
      hint: "Optional — “what would an ER visit actually cost us?”"

    ROUTABLE_SLUGS = %w[ find_care insurance_appeal ].freeze

    DISCLAIMER = "This is a plain-language reading of your document, not coverage advice — " \
      "the plan documents control, and your insurer's member services line settles anything " \
      "they don't state.".freeze

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the insurance-explainer feature of a private, self-hosted life
      assistant. The user has a health-coverage document — an insurance card,
      a Summary of Benefits and Coverage, an explanation of benefits, a letter
      from an insurer — and wants to understand it.
      Respond with a JSON object:
      {"draft": {"title": "...", "body": "..."},
       "follow_ups": [{"title": "...", "due_on": "YYYY-MM-DD" or null}, ...],
       "next_tools": [{"slug": "...", "reason": "...", "inputs": {...}}, ...]}.
      The draft's body must, in short headed parts: say what kind of document
      this is and what plan it describes; walk through the numbers the document
      itself states — premium, deductible, copays, coinsurance, out-of-pocket
      maximum — explaining each in plain language with a concrete "so a typical
      visit costs you..." reading; never state a number the document does not —
      write a [BRACKETED PLACEHOLDER] naming what to look up instead; explain
      how to find in-network care under this plan; and what to check when a
      bill doesn't match what the plan seems to promise. If the user asked a
      specific question, answer it directly under the same rules.
      follow_ups: at most #{MAX_FOLLOW_UPS} small concrete actions, each completable in a
      day, with due_on only for deadlines the document itself states, resolved
      against today's date.
      next_tools: propose "find_care" (inputs: {"specialty": "..."}) when the
      user's question points at finding a provider, and "insurance_appeal"
      when this document is a denial the user may want to appeal; omit any
      that don't apply, with a short reason each.
    PROMPT

    private
      def messages
        [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user", content: user_prompt }
        ]
      end

      def user_prompt
        parts = [ "Today's date: #{Date.current.iso8601}" ]
        parts << "The user's question: #{inputs[:question]}" if inputs[:question].present?
        parts << "The document (titled “#{document.title}”):\n#{document_text(document)}"
        parts.join("\n\n")
      end

      def document = chosen_document

      def filing_sources = [ document ]

      def handle(response)
        body = response.dig("draft", "body")
        raise Llm::Error, "The model didn't return an explanation — try again." if body.blank?

        create_note(
          title: response.dig("draft", "title").presence || "Explained — #{document.title}",
          body: [ body, DISCLAIMER ].join("\n\n")
        )
        create_follow_ups(response["follow_ups"])
        store_next_tools(with_document(response["next_tools"]), allowed: ROUTABLE_SLUGS)
      end

      # The model proposes which tool; code attaches which document (D28 —
      # model output never carries database ids).
      def with_document(proposals)
        Array(proposals).map do |proposal|
          next proposal unless proposal.is_a?(Hash) && proposal["slug"] == "insurance_appeal"

          proposal.merge("inputs" => { "document_id" => document.id.to_s })
        end
      end
  end
end
