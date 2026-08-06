module Tool
  # Shared engine for the letter family (TOOLS_PLAN wave 1): read a document
  # and/or a line of the user's own words, draft a formal letter they can
  # send, and land what sending it implies — follow-up Tasks plus any hard
  # dates as all-day calendar Events. A subclass is almost entirely prompt:
  # its SYSTEM_PROMPT, its inputs, and the sections it files under.
  #
  # Response contract every letter prompt asks for:
  #   {"letter": {"title", "body"},
  #    "follow_ups": [{"title", "due_on"}],
  #    "deadlines": [{"title", "date"}]}   # optional — omit and none land
  class LetterBase < Base
    class_attribute :letter_title_prefix, instance_accessor: false, default: nil

    self.kind = :draft

    private
      def messages
        [
          { role: "system", content: self.class::SYSTEM_PROMPT },
          { role: "user", content: user_prompt }
        ]
      end

      def user_prompt
        parts = [ "Today's date: #{Date.current.iso8601}" ]
        parts << "The user's name, for the signature: #{user.name}"
        parts.concat(prompt_parts.compact)
        if source_document
          parts << "The document (titled “#{source_document.title}”):\n#{document_text(source_document)}"
        end
        parts.join("\n\n")
      end

      # Extra user-prompt lines a subclass adds between the signature and the
      # document — the user's intent, stance, or facts. Nils are dropped.
      def prompt_parts = []

      def source_document = chosen_document

      def filing_sources = [ source_document ]

      def handle(response)
        body = response.dig("letter", "body")
        raise Llm::Error, "The model didn't return a letter — try again." if body.blank?

        create_note(
          title: response.dig("letter", "title").presence || fallback_title,
          body: [ body, note_footer ].compact.join("\n\n")
        )
        create_follow_ups(response["follow_ups"])
        create_deadline_events(response["deadlines"])
      end

      # A fixed line appended to the letter by code, not the model — for
      # warnings that must never depend on model behavior.
      def note_footer = nil

      def fallback_title
        prefix = self.class.letter_title_prefix || self.class.title
        source_document ? "#{prefix} — #{source_document.title}" : prefix
      end
  end
end
