module Tool
  # The other comp document with a signature deadline (docs/CAREER.md §3.5).
  # Total comp as actually written, the benefits translated into plain
  # dollars-and-meaning, and the red-flag scan — non-compete, arbitration,
  # clawbacks — each explained neutrally with the question to ask before
  # signing. Deadlines land on the calendar; the counter routes to
  # negotiation prep with the document attached (D28).
  class DecodeOffer < Base
    self.title = "Decode my offer"
    self.description = "Total comp, the benefits translated, the red flags named — before you sign."
    self.section_slugs = %w[ career money ]
    self.kind = :draft

    input :document_id, kind: :document, required: true,
      label: "The offer letter or contract"
    input :question,
      label: "Anything specific?",
      hint: "Optional — “is this non-compete normal?”, “what's the 401k match worth?”."

    MAX_FOLLOW_UPS = 2
    MAX_FLAGS = 5
    MAX_QUESTIONS = 5
    ROUTABLE_SLUGS = %w[ negotiation_prep ].freeze

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the offer-decoding feature of a private, self-hosted life
      assistant. The user has a job offer or employment contract in front of
      them and a deadline to sign it. Read it the way the employer's lawyer
      already has. Respond with a JSON object:
      {"decoded": {"title": "...", "body": "..."},
       "red_flags": ["...", ...],
       "questions": ["...", ...],
       "deadlines": [{"title": "...", "date": "YYYY-MM-DD"}, ...],
       "follow_ups": [{"title": "...", "due_on": "YYYY-MM-DD" or null}, ...]}.
      The decoded body, plain and jargon-free:
      - Total compensation as the document actually states it: base, bonus
        terms verbatim-in-spirit (including what makes a bonus discretionary),
        equity if any — valued only from numbers the document states, with a
        [BRACKETED PLACEHOLDER] where valuation needs outside facts.
      - The benefits, translated: what the 401k match is worth per year in
        dollars when the document states the match and salary; what the
        insurance terms mean in practice; PTO as days-you-can-actually-take.
      - What's missing: anything an offer usually states that this one
        doesn't (start date, severance, remote terms).
      Answer the user's question directly if they asked one.
      red_flags: at most #{MAX_FLAGS} — non-compete, non-solicit, mandatory arbitration,
      clawbacks, "other duties as assigned" breadth, IP assignment reach.
      Each one sentence: what the clause does in plain language, stated
      neutrally. Never assert whether a clause is enforceable in the user's
      state — that is a [verify for your state] matter.
      questions: at most #{MAX_QUESTIONS} to ask before signing, each aimed at a specific
      gap or flag above.
      deadlines: the offer's stated expiration or response date, if any.
      follow_ups: at most #{MAX_FOLLOW_UPS}, each doable in a day.
      Read only what the document states; invent nothing.
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
        parts << work_line
        parts << "The user's question: #{inputs[:question]}" if inputs[:question].present?
        parts << "The offer (titled “#{document.title}”):\n#{document_text(document)}"
        parts.compact.join("\n\n")
      end

      def document = chosen_document

      def filing_sources = [ document ]

      def handle(response)
        body = response.dig("decoded", "body")
        raise Llm::Error, "The model couldn't decode that offer — try again." if body.blank?

        flags = bulleted_block("Red flags to weigh", response["red_flags"], limit: MAX_FLAGS)
        questions = bulleted_block("Ask before signing", response["questions"], limit: MAX_QUESTIONS)
        create_note(
          title: response.dig("decoded", "title").presence || "Offer decoded — #{document.title}",
          body: [ body, flags, questions ].compact.join("\n\n")
        )
        create_deadline_events(response["deadlines"])
        create_follow_ups(response["follow_ups"], limit: MAX_FOLLOW_UPS)
        store_next_tools(
          [ { "slug" => "negotiation_prep",
              "inputs" => { "scenario" => "Countering the offer before signing",
                            "document_id" => document.id.to_s },
              "reason" => "The moment before you sign is the most leverage you'll ever have here." } ],
          allowed: ROUTABLE_SLUGS
        )
      end
  end
end
