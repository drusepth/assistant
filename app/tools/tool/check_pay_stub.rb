module Tool
  # Decode-letter's specialist for the document most workers see most often
  # and read least (docs/CAREER.md §3.3). The model explains every line in
  # plain language; the *arithmetic* — hours × rate vs gross, missing
  # overtime, rate drops, new deductions — is done by code (PayStubAudit)
  # and appended as its own block, so a wage-theft signal never depends on
  # model behavior. A short result routes to the wage-claim letter with the
  # stub attached (D28).
  class CheckPayStub < Base
    self.title = "Check my pay stub"
    self.description = "Every line explained in plain language — and the math checked by the app."
    self.section_slugs = %w[ career money ]
    self.kind = :draft

    input :document_id, kind: :document, required: true,
      label: "Which pay stub?"
    input :question,
      label: "Anything specific?",
      hint: "Optional — “why did my net pay drop?”, “what is OASDI?”."

    MAX_FOLLOW_UPS = 2
    MAX_FINDINGS = 6
    ROUTABLE_SLUGS = %w[ wage_claim ].freeze

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the pay-stub-checking feature of a private, self-hosted life
      assistant. The user has a pay stub; almost nobody was ever shown how to
      read one. Explain it. Respond with a JSON object:
      {"explanation": {"title": "...", "body": "..."},
       "follow_ups": [{"title": "...", "due_on": "YYYY-MM-DD" or null}, ...]}.
      The explanation body, in plain jargon-free language: what each line and
      deduction on this stub is (what OASDI/FICA actually funds, what a 401k
      line means, pre-tax vs after-tax); how gross became net on this stub;
      and — when facts from a previous stub are provided — what changed and
      why the numbers moved. Answer the user's question directly if they asked
      one. Read only what the stub states: never invent amounts, and where
      something is unclear say so plainly. Do not check the arithmetic — the
      app does that itself and appends the result.
      follow_ups: at most #{MAX_FOLLOW_UPS}, only when the stub itself implies an action
      (an expiring election, a missing enrollment), each doable in a day.
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
        parts << "The pay stub (titled “#{document.title}”):\n#{document_text(document)}"
        if (previous = previous_stub)
          parts << "Extracted facts from the previous stub (#{previous.logged_on.iso8601}), for comparison:\n#{facts_line(previous)}"
        end
        parts.compact.join("\n\n")
      end

      def document = chosen_document

      def stub
        return @stub if defined?(@stub)
        @stub = Career::PayStub.for(document)
      end

      def previous_stub
        return @previous_stub if defined?(@previous_stub)
        @previous_stub = stub && Career::PayStub.previous_for(stub)
      end

      def audit
        @audit ||= stub && Career::PayStubAudit.new(stub, previous: previous_stub)
      end

      def facts_line(pay_stub)
        [
          pay_stub.employer && "employer: #{pay_stub.employer}",
          pay_stub.rate && "rate: #{pay_stub.rate.to_s("F")}/hr",
          pay_stub.hours && "hours: #{pay_stub.hours.to_s("F")}",
          pay_stub.gross && "gross: #{pay_stub.gross.to_s("F")}",
          pay_stub.net && "net: #{pay_stub.net.to_s("F")}",
          pay_stub.deductions.any? && "deductions: #{pay_stub.deductions.map { |label, _| label }.join(", ")}"
        ].select(&:itself).join("; ")
      end

      def filing_sources = [ document ]

      def handle(response)
        body = response.dig("explanation", "body")
        raise Llm::Error, "The model couldn't explain that stub — try again." if body.blank?

        numbers = audit && bulleted_block(
          "What the numbers say (checked by the app, not the AI)",
          audit.findings, limit: MAX_FINDINGS
        )
        create_note(
          title: response.dig("explanation", "title").presence || "Pay stub check — #{document.title}",
          body: [ body, numbers ].compact.join("\n\n")
        )
        create_follow_ups(response["follow_ups"], limit: MAX_FOLLOW_UPS)

        if audit&.concerning?
          store_next_tools(
            [ { "slug" => "wage_claim",
                "inputs" => { "document_id" => document.id.to_s,
                              "details" => audit.concerning_findings.first.to_s },
                "reason" => "The numbers came up short — a written demand is how a shortfall becomes back pay." } ],
            allowed: ROUTABLE_SLUGS
          )
        end
      end
  end
end
