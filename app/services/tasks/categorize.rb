module Tasks
  # Auto-sorting for quick-added tasks: the user types one line, and the
  # household's model files it into sections and picks up any due date the
  # line implies ("renew passport by Friday"). Unlike document analysis
  # (suggest-and-click), results are applied directly — the whole point is
  # that the user never touches a categorization form.
  class Categorize
    MAX_SECTIONS = 3
    MAX_QUESTIONS = 3

    Result = Data.define(:sections, :due_on, :questions)

    def initialize(task:, profile:)
      @task = task
      @profile = profile
    end

    def call
      response = @profile.client.chat(messages, json: true)

      Result.new(
        sections: Llm::Taxonomy.match(response["sections"], limit: MAX_SECTIONS),
        due_on: parsed_date(response["due_on"]),
        questions: parsed_questions(response["questions"])
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
          You are the task-sorting feature of a private, self-hosted life assistant.
          The user jots tasks down as a single line; you file each one so they never
          have to fill in a form. Respond with a JSON object:
          {"sections": ["slug", ...], "due_on": "YYYY-MM-DD" or null,
           "questions": ["...", ...]}.
          Choose at most #{MAX_SECTIONS} sections, only from the provided list, ordered by
          relevance; choose none if nothing clearly fits.
          Set due_on only when the task states or clearly implies a date ("by Friday",
          "before April 15"), resolved against today's date; otherwise use null.
          questions: when the task is mental work an assistant could help with in
          conversation — deciding, choosing, brainstorming, drafting, planning,
          researching — give one or two short opening questions, posed directly to
          the user, that would move the task toward an answer or surface what the
          answer depends on. Use an empty array when the task is a physical errand
          or quick action a conversation wouldn't help with.
        PROMPT
      end

      def user_prompt
        parts = [ "Today's date: #{Date.current.iso8601} (#{Date.current.strftime("%A")})" ]
        parts << "Task: #{@task.title}"
        parts << "Notes: #{@task.notes}" if @task.notes.present?
        parts << "Available sections (slug — meaning):\n#{Llm::Taxonomy.listing}"
        parts.join("\n\n")
      end

      def parsed_date(value)
        return nil if value.blank?

        Date.iso8601(value.to_s)
      rescue Date::Error
        nil
      end

      def parsed_questions(value)
        Array(value).grep(String).map(&:strip).reject(&:empty?).first(MAX_QUESTIONS)
      end
  end
end
