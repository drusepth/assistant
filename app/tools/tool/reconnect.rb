module Tool
  # Staying in touch is the People section's core promise: pick a person,
  # get a warm message draft plus talking points from what you've noted
  # about them. Deliberately seeds the M3 stay-in-touch watcher, whose
  # accept action opens this tool prefilled.
  class Reconnect < Base
    self.title = "Reconnect with someone"
    self.description = "A warm message draft and talking points, from what you know about them."
    self.section_slugs = %w[ people ]
    self.kind = :draft

    input :person_id, kind: :person, required: true,
      label: "Who do you want to reach out to?"
    input :context,
      label: "Anything going on?",
      hint: "Optional — “her birthday's coming up”, “heard he changed jobs”."

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the reconnect feature of a private, self-hosted life assistant.
      The user wants to reach out to someone they haven't talked to in a while.
      The draft is a short, warm message (readable as a text or an email) plus,
      under it, 3 bullet talking points drawn from what's known about the
      person. Sound like a person, not a card: specific over generic, no
      guilt about the gap, one genuine question they'd actually want to answer.
      follow_ups: at most one — send it.
      #{DRAFT_FORMAT}
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
        parts << "Reaching out to: #{person.name}"
        parts << "Relationship: #{person.relationship}" if person.relationship.present?
        parts << "Birthday: #{person.birthday.strftime("%B %-d")}" if person.birthday
        parts << "Last logged contact: #{person.last_contacted_on.iso8601}" if person.respond_to?(:last_contacted_on) && person.last_contacted_on
        parts << "What the user has noted about them:\n#{person.notes.truncate(2_000)}" if person.notes.present?
        parts << "What's going on: #{inputs[:context]}" if inputs[:context].present?
        parts.join("\n\n")
      end

      def person
        @person ||= Person.visible_to(user).find_by(id: inputs[:person_id]) ||
          raise(Llm::Error, "That person is gone or no longer shared with you.")
      end

      def fallback_title = "Message to #{person.name}"

      # Filed under People plus wherever the person themselves is filed.
      def filing
        @filing ||= (self.class.section_records + person.sections).uniq
      end
  end
end
