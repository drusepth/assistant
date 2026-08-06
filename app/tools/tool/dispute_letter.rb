module Tool
  # The first tool (M2.1) and the mission's heart: turn a bill, a denial, or
  # a collection notice into a formal dispute letter the user can send, plus
  # the follow-up steps sending it implies. Tier A (D19): reads only what's
  # already in the vault — no web capability assumed.
  class DisputeLetter < Base
    self.title = "Draft a dispute letter"
    self.description = "Turn a bill, denial, or collection notice into a formal letter you can send."
    self.section_slugs = %w[ disputes ]
    self.kind = :draft

    input :document_id, kind: :document, required: true,
      label: "Which document is this about?"
    input :intent,
      label: "What outcome do you want?",
      hint: "One line — “this charge is wrong, remove it”, “approve the claim”."

    MAX_FOLLOW_UPS = 3
    MAX_DOCUMENT_CHARS = 15_000

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the dispute-letter feature of a private, self-hosted life assistant.
      The user has a document — a bill, a denial, a collection notice — they want
      to push back on. Draft a firm, factual, formal letter they can send, and list
      the follow-up steps sending it implies. Respond with a JSON object:
      {"letter": {"title": "...", "body": "..."},
       "follow_ups": [{"title": "...", "due_on": "YYYY-MM-DD" or null}, ...]}.
      The letter must: state the dispute and the requested outcome in the first
      paragraph; cite dates, amounts, and reference numbers from the document when
      present; request written confirmation and a response deadline; stay polite,
      specific, and unemotional; invent nothing — where a detail is unknown, leave
      a [BRACKETED PLACEHOLDER] for the user to fill in.
      follow_ups are at most #{MAX_FOLLOW_UPS} small concrete actions (send the letter, chase a
      reply, gather a missing record), each completable in a day; set due_on only
      when the document states or clearly implies a deadline, resolved against
      today's date.
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
        parts << "The user's name, for the signature: #{user.name}"
        parts << "What the user wants: #{inputs[:intent]}" if inputs[:intent].present?
        parts << "The document (titled “#{document.title}”):\n#{document_text}"
        parts.join("\n\n")
      end

      def document
        @document ||= Document.visible_to(user).find_by(id: inputs[:document_id]) ||
          raise(Llm::Error, "That document is gone or no longer shared with you.")
      end

      def document_text
        text = document.extracted_text.presence || document.summary.presence
        raise Llm::Error, "That document has no readable text yet — open it and run Analyze first." unless text

        text.truncate(MAX_DOCUMENT_CHARS)
      end

      def handle(response)
        body = response.dig("letter", "body")
        raise Llm::Error, "The model didn't return a letter — try again." if body.blank?

        letter = record(user.notes.create!(
          title: response.dig("letter", "title").presence || "Dispute letter — #{document.title}",
          body: body
        ))
        letter.sections = filing

        Array(response["follow_ups"]).first(MAX_FOLLOW_UPS).each do |step|
          next unless step.is_a?(Hash) && step["title"].present?

          due_on = parsed_date(step["due_on"])
          task = record(user.tasks.create!(
            title: step["title"].to_s, due_on: due_on,
            bucket: due_on && due_on <= Date.current ? :today : :later
          ))
          task.sections = filing
        end
      end

      # The letter and its follow-ups are always findable where the tool
      # lives (Rights → Disputes) and inherit the document's own filing.
      def filing
        @filing ||= (self.class.section_records + document.sections).uniq
      end
  end
end
