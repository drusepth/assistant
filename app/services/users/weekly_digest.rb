module Users
  # The M3.3 Dashboard digest: the one place the agent uses the LLM — and
  # only to *phrase*, never to decide. Everything it may talk about is
  # gathered deterministically below (counts, titles, pending suggestions);
  # the model turns that into two or three warm sentences. Failure is
  # silent: the Dashboard's locally-computed summary always stands on its
  # own.
  class WeeklyDigest
    MAX_ITEMS = 8

    def initialize(user:, profile:)
      @user = user
      @profile = profile
    end

    def call
      text = @profile.client.chat(messages).to_s.strip
      return if text.blank?

      @user.update!(digest: text.truncate(600), digest_generated_at: Time.current)
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
          You are the weekly digest of a private, self-hosted life assistant.
          From the facts below — and ONLY the facts below, invent nothing —
          write two or three plain sentences telling the user where their week
          stands and the one or two things most worth doing first. Warm,
          concrete, no markdown, no greetings, no exclamation marks. If there
          is genuinely little going on, say so briefly — that's good news.
        PROMPT
      end

      def user_prompt
        overdue = @user.tasks.open.where(due_on: ...Date.current)
        due_today = @user.tasks.open.where(due_on: Date.current)
        events = @user.events.where(starts_at: Time.current..7.days.from_now.end_of_day).order(:starts_at)
        suggestions = @user.suggestions.actionable

        parts = [ "Today's date: #{Date.current.iso8601} (#{Date.current.strftime("%A")})" ]
        parts << "Overdue tasks (#{overdue.count}): #{titles(overdue)}" if overdue.any?
        parts << "Tasks due today (#{due_today.count}): #{titles(due_today)}" if due_today.any?
        parts << "Events in the next 7 days: #{events.limit(MAX_ITEMS).map { |e| "#{e.title} (#{e.starts_at.strftime("%a %b %-d")})" }.join("; ")}" if events.any?
        parts << "Pending suggestions from the assistant: #{titles(suggestions)}" if suggestions.any?
        parts << "Nothing overdue, nothing due today, no upcoming events." if parts.size == 1
        parts.join("\n")
      end

      def titles(scope)
        scope.limit(MAX_ITEMS).map(&:title).join("; ")
      end
  end
end
