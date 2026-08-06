module People
  # Auto-sorting for quick-added people (D16): the user gives a name and
  # maybe a line about who they are; the household's model files them into
  # sections and fills in the relationship label if one is stated.
  class Categorize
    MAX_SECTIONS = 3
    RELATIONSHIP_LIMIT = 40

    Result = Data.define(:sections, :relationship)

    def initialize(person:, profile:)
      @person = person
      @profile = profile
    end

    def call
      response = @profile.client.chat(messages, json: true)

      Result.new(
        sections: Llm::Taxonomy.match(response["sections"], limit: MAX_SECTIONS),
        relationship: response["relationship"].to_s.strip.truncate(RELATIONSHIP_LIMIT)
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
          You are the people-filing feature of a private, self-hosted life assistant.
          The user adds a person with a name and maybe a note about them; you file each
          one so they never have to fill in a form. Respond with a JSON object:
          {"sections": ["slug", ...], "relationship": "..." or null}.
          Choose at most #{MAX_SECTIONS} sections, only from the provided list, ordered by
          relevance; choose none if nothing clearly fits.
          The relationship is a short label for who this person is to the user
          ("mom", "landlord", "cardiologist") — only when it's clearly stated; otherwise null.
        PROMPT
      end

      def user_prompt
        parts = [ "Person: #{@person.name}" ]
        parts << "Notes: #{@person.notes}" if @person.notes.present?
        parts << "Available sections (slug — meaning):\n#{Llm::Taxonomy.listing}"
        parts.join("\n\n")
      end
  end
end
