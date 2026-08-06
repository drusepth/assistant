module Goals
  # Auto-sorting for quick-added goals (D16): the user names what they're
  # working toward; the household's model files it into sections and picks
  # up any target date the title implies ("save $5k by December").
  class Categorize
    MAX_SECTIONS = 3

    Result = Data.define(:sections, :target_on)

    def initialize(goal:, profile:)
      @goal = goal
      @profile = profile
    end

    def call
      response = @profile.client.chat(messages, json: true)

      Result.new(
        sections: Llm::Taxonomy.match(response["sections"], limit: MAX_SECTIONS),
        target_on: parsed_date(response["target_on"])
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
          You are the goal-sorting feature of a private, self-hosted life assistant.
          The user jots goals down as a single line; you file each one so they never
          have to fill in a form. Respond with a JSON object:
          {"sections": ["slug", ...], "target_on": "YYYY-MM-DD" or null}.
          Choose at most #{MAX_SECTIONS} sections, only from the provided list, ordered by
          relevance; choose none if nothing clearly fits.
          Set target_on only when the goal states or clearly implies a target date
          ("by December", "before the wedding in June"), resolved against today's date;
          otherwise use null.
        PROMPT
      end

      def user_prompt
        parts = [ "Today's date: #{Date.current.iso8601} (#{Date.current.strftime("%A")})" ]
        parts << "Goal: #{@goal.title}"
        parts << "Description: #{@goal.description}" if @goal.description.present?
        parts << "Available sections (slug — meaning):\n#{Llm::Taxonomy.listing}"
        parts.join("\n\n")
      end

      def parsed_date(value)
        return nil if value.blank?

        Date.iso8601(value.to_s)
      rescue Date::Error
        nil
      end
  end
end
