module Tool
  # Relationships fade by default; a small nudge and a ready-to-send message
  # beat good intentions. Reads a Person and what's recorded about them into
  # a short message in the user's own voice plus grounded talking points.
  # The hard guardrail: never invent shared memories — warmth that isn't
  # backed by a recorded fact stays generic. This tool deliberately seeds
  # the Milestone 3 stay-in-touch watcher: its accept action runs this
  # prefilled (ROADMAP §3).
  class Reconnect < Base
    self.title = "Reconnect with someone"
    self.description = "A ready-to-send message and talking points, from what you know about them."
    self.section_slugs = %w[ people ]
    self.kind = :draft

    input :person_id, kind: :person, required: true,
      label: "Who?"
    input :occasion,
      label: "Any reason or occasion?",
      hint: "Optional — “her birthday's coming up”, “just checking in”."

    MAX_TALKING_POINTS = 5
    MAX_FOLLOW_UPS = 2

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the reconnect feature of a private, self-hosted life assistant.
      The user wants to get back in touch with someone; draft the opener for
      them. Respond with a JSON object:
      {"message": {"title": "...", "body": "..."},
       "talking_points": ["...", ...],
       "follow_ups": [{"title": "...", "due_on": "YYYY-MM-DD" or null}, ...]}.
      The message is a short, warm text-or-email opener written in the user's
      own casual voice — a few sentences, no greeting-card language, no
      apology-spiral about the silence (one light acknowledgment at most). Ground
      it in the recorded facts: the relationship, the occasion, something known
      about them. Never invent shared memories, inside jokes, or events the
      provided data doesn't state — when little is recorded, stay warmly generic
      and ask a real question instead.
      talking_points: up to #{MAX_TALKING_POINTS} short prompts for the conversation once it
      starts, each grounded in a recorded fact ("ask how the new job is going")
      or honestly open ("find out what they've been up to — it's been a while").
      follow_ups: at most #{MAX_FOLLOW_UPS} — send the message, and when momentum warrants,
      a suggestion to make a concrete plan; due_on resolved against today.
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
        parts << "The user's name: #{user.name}"
        parts << "Occasion: #{inputs[:occasion]}" if inputs[:occasion].present?
        parts << "The person, as recorded:\n#{person_facts}"
        parts.join("\n\n")
      end

      def person_facts
        facts = [ "Name: #{person.name}" ]
        facts << "Relationship: #{person.relationship}" if person.relationship.present?
        facts << "Birthday: #{person.birthday.iso8601}" if person.birthday
        facts << "Notes about them: #{person.notes}" if person.notes.present?
        facts.join("\n")
      end

      def person = chosen_person

      def filing_sources = [ person ]

      def handle(response)
        body = response.dig("message", "body")
        raise Llm::Error, "The model didn't return a message — try again." if body.blank?

        create_note(
          title: response.dig("message", "title").presence || "Reconnect with #{person.name}",
          body: [
            body,
            bulleted_block("Talking points", response["talking_points"], limit: MAX_TALKING_POINTS)
          ].compact.join("\n\n")
        )
        create_follow_ups(response["follow_ups"], limit: MAX_FOLLOW_UPS)
      end
  end
end
