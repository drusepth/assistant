module Events
  # Auto-sorting for quick-added events (D16): the user gives a title and a
  # day; the household's model files it into sections and picks up any
  # time of day the title implies ("dentist at 3pm"). Times are returned
  # relative to the day the user already chose — the model never moves the
  # event to a different date.
  class Categorize
    MAX_SECTIONS = 3

    Result = Data.define(:sections, :starts_at, :ends_at)

    def initialize(event:, profile:)
      @event = event
      @profile = profile
    end

    def call
      response = @profile.client.chat(messages, json: true)

      Result.new(
        sections: Llm::Taxonomy.match(response["sections"], limit: MAX_SECTIONS),
        starts_at: at_time(response["start_time"]),
        ends_at: at_time(response["end_time"])
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
          You are the event-sorting feature of a private, self-hosted life assistant.
          The user jots events down as a title and a day; you file each one so they never
          have to fill in a form. Respond with a JSON object:
          {"sections": ["slug", ...], "start_time": "HH:MM" or null, "end_time": "HH:MM" or null}.
          Choose at most #{MAX_SECTIONS} sections, only from the provided list, ordered by
          relevance; choose none if nothing clearly fits.
          Set start_time and end_time (24-hour clock) only when the event states or clearly
          implies a time of day ("dentist at 3pm", "dinner 7-9pm"); otherwise use null.
        PROMPT
      end

      def user_prompt
        parts = [ "Today's date: #{Date.current.iso8601} (#{Date.current.strftime("%A")})" ]
        parts << "Event: #{@event.title}"
        parts << "On: #{@event.starts_at.to_date.iso8601}"
        parts << "Location: #{@event.location}" if @event.location.present?
        parts << "Description: #{@event.description}" if @event.description.present?
        parts << "Available sections (slug — meaning):\n#{Llm::Taxonomy.listing}"
        parts.join("\n\n")
      end

      def at_time(value)
        hour, minute = value.to_s.match(/\A(\d{1,2}):(\d{2})\z/)&.captures
        return nil unless hour && hour.to_i < 24 && minute.to_i < 60

        @event.starts_at.change(hour: hour.to_i, min: minute.to_i)
      end
  end
end
