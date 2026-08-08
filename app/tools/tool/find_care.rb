module Tool
  # The canonical Q9 reframe from ROADMAP.md, finally built: "find
  # in-network cardiologists" without the capability lie. Tier A — the
  # model can't browse, so it never invents a provider, network, phone
  # number, or address; instead it reads the insurance documents already in
  # the vault and produces the plan: where the real in-network directory
  # lives, how to search it for this kind of provider, a call script for
  # offices, and what to weigh when choosing. The verify-before-you-book
  # warning is appended by code, so the guardrail never depends on model
  # behavior. The care radar's "Find a provider" links land here prefilled.
  class FindCare < Base
    self.title = "Find a doctor"
    self.description = "A plan for finding the right in-network provider — where to look, what to ask, a call script."
    self.section_slugs = %w[ health ]
    self.kind = :draft

    input :specialty, required: true,
      label: "What kind of provider?",
      hint: "“primary care doctor”, “dentist”, “eye doctor”, “dermatologist”…"
    input :details,
      label: "Anything that matters?",
      hint: "Optional — “taking new patients”, “evening hours”, “Spanish-speaking”, your area."

    MAX_COVERAGE_DOCS = 2
    MAX_SUMMARY_CHARS = 500

    VERIFY_FOOTER = "Before you book: a front desk saying “we take your insurance” is not " \
      "the same as in-network. Confirm directly with your insurer — the member services " \
      "number on your card — and note the date and the name of who confirmed it.".freeze

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the find-care feature of a private, self-hosted life assistant.
      The user needs to find a provider. You cannot browse the web, so be
      honest about what you know: NEVER invent a specific provider, practice,
      network status, address, phone number, or price. The draft is their
      search plan, with short headed parts: where the real in-network list
      lives (their insurer's member portal or member services line — use the
      insurer's actual name when their documents below state it, a [BRACKETED
      PLACEHOLDER] otherwise) and exactly what to search it for given the kind
      of provider they need; other legitimate places to look and vet
      (state licensing boards, community health centers if cost is a concern);
      a short call script for a provider's office covering new patients,
      scheduling, and costs; and what's worth weighing when choosing.
      Tailor everything to the specialty and the user's stated needs.
      #{DRAFT_FORMAT}
      follow_ups are small concrete actions ("pull up the member portal and
      shortlist three offices", "call two offices from the shortlist").
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
        parts << "Provider needed: #{inputs[:specialty]}"
        parts << "What matters to the user: #{inputs[:details]}" if inputs[:details].present?
        parts << coverage_block
        parts.compact.join("\n\n")
      end

      def coverage_block
        return nil if coverage_documents.none?

        rows = coverage_documents.map do |document|
          "- #{document.title}#{": #{document.summary.truncate(MAX_SUMMARY_CHARS)}" if document.summary.present?}"
        end
        "Insurance documents on file (for the insurer's name and how this plan finds in-network care):\n#{rows.join("\n")}"
      end

      def coverage_documents
        @coverage_documents ||= Health::Coverage.documents(user, limit: MAX_COVERAGE_DOCS)
      end

      def filing_sources = coverage_documents

      def handle(response)
        body = response.dig("draft", "body")
        raise Llm::Error, "The model didn't return a draft — try again." if body.blank?

        create_note(
          title: response.dig("draft", "title").presence || fallback_title,
          body: [ body, VERIFY_FOOTER ].join("\n\n")
        )
        create_follow_ups(response["follow_ups"])
      end

      def fallback_title = "Finding care — #{inputs[:specialty].to_s.squish.presence || "a provider"}"
  end
end
