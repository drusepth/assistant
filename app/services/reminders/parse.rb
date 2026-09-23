module Reminders
  # Plain words into the new-task form (D-standing-reminders,
  # D-reminders-on-tasks): "take the trash out every Thursday night" becomes
  # a title (`body`), a first day, a time, and a Repeat — the task form's
  # own fields, prefilled for the user to check and send. The model reads the sentence; nothing lands without the click
  # (D20), and the closed sets (`Reminder::REPEAT_OPTIONS`, the weekday
  # codes) are what its answer is validated into. Same shape as
  # Tasks::Categorize: one call, one JSON object, deterministic parsing of
  # what comes back.
  class Parse
    Result = Data.define(:body, :deliver_on, :deliver_time, :repeat, :repeat_days, :repeat_until) do
      def attributes = to_h.compact
    end

    def initialize(text:, profile:, zone:)
      @text = text.to_s.strip
      @profile = profile
      @zone = zone
    end

    def call
      response = @profile.client.chat(messages, json: true)

      Result.new(
        body: response["body"].to_s.strip.truncate(Reminder::MAX_BODY).presence || @text.truncate(Reminder::MAX_BODY),
        deliver_on: parsed_date(response["date"]) || today,
        deliver_time: parsed_time(response["time"]),
        repeat: Reminder::REPEAT_OPTIONS.key?(response["repeat"]) ? response["repeat"] : "none",
        repeat_days: Array(response["days"]).grep(String).map(&:upcase).select { |code| Recurrence::Rule::WEEKDAYS.key?(code) },
        repeat_until: parsed_date(response["until"])
      )
    end

    private
      def today = Time.current.in_time_zone(@zone).to_date

      def messages
        [
          { role: "system", content: system_prompt },
          { role: "user", content: user_prompt }
        ]
      end

      def system_prompt
        <<~PROMPT
          You fill in the new-task form of a private, self-hosted life assistant.
          The user says in plain words what they need to do, when, and whether it
          repeats; you fill in the form for them. Respond with a JSON object:
          {"body": "...", "date": "YYYY-MM-DD" or null, "time": "HH:MM" or null,
           "repeat": one of #{Reminder::REPEAT_OPTIONS.keys.map(&:inspect).join(", ")},
           "days": ["MO", "TU", "WE", "TH", "FR", "SA", "SU"] or [], "until": "YYYY-MM-DD" or null}.
          body is the task, as a short imperative phrase in the user's own
          words with the timing removed ("take the trash out", "call the pharmacy").
          date is the first day it should fire, resolved against today's date: a named
          day ("Thursday") means the coming one, "tonight" means today, "tomorrow
          morning" means tomorrow; null if none is stated.
          time is 24-hour, resolved from the words: "morning" 09:00, "noon" 12:00,
          "afternoon" 15:00, "evening" 18:00, "night" 20:00; null if none is stated.
          repeat is "none" unless the user asks for it to recur: "every day" daily,
          "weekdays" weekdays, "every Thursday" or "every week" weekly, "every other
          week" biweekly, "every month" or "on the 1st of every month" monthly,
          "every year" yearly. days lists the weekdays for weekly and biweekly only
          ("Mondays and Fridays" is ["MO", "FR"]); otherwise [].
          until is the last day, only when the user gives one ("until the end of
          March", "through December"); otherwise null.
        PROMPT
      end

      def user_prompt
        "Today's date: #{today.iso8601} (#{today.strftime("%A")})\n\nThe user said: #{@text}"
      end

      def parsed_date(value)
        return nil if value.blank?

        Date.iso8601(value.to_s)
      rescue Date::Error
        nil
      end

      def parsed_time(value)
        match = value.to_s.strip.match(/\A(\d{1,2}):(\d{2})\z/)
        return nil unless match && match[1].to_i < 24 && match[2].to_i < 60

        format("%02d:%s", match[1].to_i, match[2])
      end
  end
end
