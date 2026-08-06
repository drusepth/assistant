module Notes
  # Auto-sorting for quick-jotted notes (D16): the user types only a body;
  # the household's model files it into sections and gives it a short title
  # so the notes list stays scannable.
  class Categorize
    MAX_SECTIONS = 3
    TITLE_LIMIT = 80

    Result = Data.define(:sections, :title)

    def initialize(note:, profile:)
      @note = note
      @profile = profile
    end

    def call
      response = @profile.client.chat(messages, json: true)

      Result.new(
        sections: Llm::Taxonomy.match(response["sections"], limit: MAX_SECTIONS),
        title: response["title"].to_s.strip.truncate(TITLE_LIMIT)
      )
    end

    private
      def messages
        [
          { role: "system", content: system_prompt },
          { role: "user", content: user_prompt }
        ]
      end

      def system_prompt
        <<~PROMPT
          You are the note-filing feature of a private, self-hosted life assistant.
          The user jots notes down as plain text; you file each one so they never
          have to fill in a form. Respond with a JSON object:
          {"sections": ["slug", ...], "title": "..."}.
          Choose at most #{MAX_SECTIONS} sections, only from the provided list, ordered by
          relevance; choose none if nothing clearly fits.
          The title is a short label for the note, at most 8 words, in the note's own language.
        PROMPT
      end

      def user_prompt
        parts = [ "Note:\n#{@note.body}" ]
        parts << "Available sections (slug — meaning):\n#{Llm::Taxonomy.listing}"
        parts.join("\n\n")
      end
  end
end
