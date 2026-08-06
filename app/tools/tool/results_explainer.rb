module Tool
  # Test results in plain language — comprehension, not diagnosis (the
  # PRODUCT.md health scoping, carefully kept). The model explains what the
  # document itself says and where it marks values against its own reference
  # ranges; it never infers new diagnoses or suggests treatment. The
  # disclaimer is appended by code, so the guardrail never depends on model
  # behavior — and neither does the doctor-questions checklist formatting.
  class ResultsExplainer < Base
    self.title = "Explain my results"
    self.description = "Lab results or a diagnosis letter in plain language, plus what to ask your doctor."
    self.section_slugs = %w[ health ]
    self.kind = :draft

    input :document_id, kind: :document, required: true,
      label: "Which results are these?"
    input :question,
      label: "Anything specific you're wondering?",
      hint: "Optional — “what does the cholesterol number mean?”"

    MAX_QUESTIONS = 6
    MAX_FOLLOW_UPS = 2

    DISCLAIMER = "This explains what the document says in plain language — it is " \
      "not a diagnosis or medical advice. Your doctor is the right person to " \
      "interpret these results.".freeze

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the results-explainer feature of a private, self-hosted life
      assistant. The user has a medical document — lab results, an imaging report,
      a diagnosis letter, an explanation of benefits — and wants to understand it.
      Respond with a JSON object:
      {"explanation": {"title": "...", "body": "..."},
       "questions_for_doctor": ["...", ...],
       "follow_ups": [{"title": "...", "due_on": "YYYY-MM-DD" or null}, ...]}.
      The explanation must: say what kind of document this is and what it covers;
      walk through each result, term, or code in plain language a layperson
      understands; where the document itself marks a value as inside or outside
      its reference range, say so — never judge a value against ranges the
      document does not state; explain terminology without inferring any new
      diagnosis, speculating about severity, or suggesting treatment changes —
      "ask your doctor about X" is the ceiling. If the user asked a specific
      question, address it directly under the same rules.
      questions_for_doctor: up to #{MAX_QUESTIONS} short, concrete questions this document
      raises that are worth asking at the next appointment.
      follow_ups: at most #{MAX_FOLLOW_UPS}, and only actions the document itself states — a
      recommended follow-up test, a repeat in N months — with due_on resolved
      against today's date.
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
        body = response.dig("explanation", "body")
        raise Llm::Error, "The model didn't return an explanation — try again." if body.blank?

        create_note(
          title: response.dig("explanation", "title").presence || "Explained — #{document.title}",
          body: [ body, questions_block(response["questions_for_doctor"]), DISCLAIMER ].compact.join("\n\n")
        )
        create_follow_ups(response["follow_ups"], limit: MAX_FOLLOW_UPS)
      end

      def questions_block(questions)
        questions = Array(questions).grep(String).map(&:strip).reject(&:empty?).first(MAX_QUESTIONS)
        return nil if questions.none?

        "Questions for your doctor:\n#{questions.map { |question| "- #{question}" }.join("\n")}"
      end
  end
end
