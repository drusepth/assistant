module Tool
  # The visit is fifteen minutes; the history is years. The first tool that
  # reads a *section* rather than a single document: everything Health-tagged
  # the user can see becomes a one-page visit sheet — dated history, what's
  # unresolved, and the questions worth the appointment time. Strictly what
  # the vault states: gaps become [BRACKETED PLACEHOLDER] lines, never
  # plausible history (D16 discipline applied to reading, not just writing).
  class DoctorVisitPrep < Base
    self.title = "Prep for a doctor visit"
    self.description = "A one-page visit sheet from what you've tracked — history, what's unresolved, what to ask."
    self.section_slugs = %w[ health ]
    self.kind = :draft

    input :reason, required: true,
      label: "What's the visit about?",
      hint: "“Annual physical”, “follow-up on the MRI with Dr. Chen”."

    MAX_QUESTIONS = 8
    MAX_FOLLOW_UPS = 2

    FOOTER = "Built only from what you've tracked in this app — bring anything newer with you.".freeze

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the doctor-visit-prep feature of a private, self-hosted life
      assistant. The user has an appointment coming up; build the one-page sheet
      they should walk in with, from their tracked health data. Respond with a
      JSON object:
      {"prep": {"title": "...", "body": "..."},
       "questions": ["...", ...],
       "follow_ups": [{"title": "...", "due_on": "YYYY-MM-DD" or null}, ...]}.
      The prep body is the visit sheet: the reason for the visit; a short dated
      timeline of relevant history drawn strictly from the provided data — visits,
      symptoms, results, medications — most recent first; and anything the data
      shows as unresolved (an abnormal result never followed up, a symptom that
      keeps recurring). Use only what the provided data states: never fill gaps
      with plausible history, and where something a doctor will ask for is missing
      (current medications, allergies), include a [BRACKETED PLACEHOLDER] line for
      the user to complete before the visit.
      questions: up to #{MAX_QUESTIONS} short, concrete questions worth asking at this visit,
      each grounded in the data or the visit reason — an unexplained result, a due
      screening, a medication question. Never "any questions you have".
      follow_ups: at most #{MAX_FOLLOW_UPS}, and only preparation actions (gather a record,
      write down current medications), with due_on resolved against today's date.
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
        parts << "The visit: #{inputs[:reason]}"
        context = section_context
        parts << if context.empty?
          "No tracked health data yet — build the sheet from the visit reason, with placeholders for the rest."
        else
          "What the user has tracked (Health):\n#{context.to_prompt}"
        end
        parts.join("\n\n")
      end

      def handle(response)
        body = response.dig("prep", "body")
        raise Llm::Error, "The model didn't return a visit sheet — try again." if body.blank?

        create_note(
          title: response.dig("prep", "title").presence || "Visit sheet — #{inputs[:reason]}",
          body: [
            body,
            bulleted_block("Questions to ask", response["questions"], limit: MAX_QUESTIONS),
            FOOTER
          ].compact.join("\n\n")
        )
        create_follow_ups(response["follow_ups"], limit: MAX_FOLLOW_UPS)
      end
  end
end
