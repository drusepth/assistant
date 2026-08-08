module Goals
  # The heart of the merged Tasks section (D17): the user names an outcome
  # ("get a job", "fight the eviction") and the household's model turns it
  # into day-sized scheduled steps — plus the goal's own sections and target
  # date — in a single call. This absorbs what Goals::Categorize used to do.
  # When the goal already has steps, the model sees them and proposes only
  # what's missing, so "suggest more steps" appends instead of clobbering.
  class BreakDown
    MAX_SECTIONS = 3
    MAX_STEPS = 10
    MAX_QUESTIONS = 3

    Step = Data.define(:title, :notes, :due_on, :sections, :questions)
    Result = Data.define(:sections, :target_on, :steps)

    # brief is optional framing from whatever captured the goal — a plan
    # tool shaping its steps (D19). It rides the same prompt; plan tools
    # add no pipeline and no schema of their own.
    def initialize(goal:, profile:, brief: nil)
      @goal = goal
      @profile = profile
      @brief = brief
    end

    def call
      response = @profile.client.chat(messages, json: true)

      Result.new(
        sections: Llm::Taxonomy.match(response["sections"], limit: MAX_SECTIONS),
        target_on: parsed_date(response["target_on"]),
        steps: parsed_steps(response["steps"])
      )
    end

    # Call + apply in one: files the goal (hand-tagged goals are left alone),
    # fills a missing target date, creates the scheduled step tasks. Returns
    # the created tasks; raises Llm::Error for callers to handle.
    def plan!
      result = call

      @goal.sections = result.sections if @goal.sections.none?
      @goal.update!(target_on: result.target_on) if @goal.target_on.nil? && result.target_on

      result.steps.map do |step|
        task = @goal.user.tasks.create!(
          goal: @goal, title: step.title, notes: step.notes, due_on: step.due_on,
          guiding_questions: step.questions,
          bucket: step.due_on && step.due_on <= Date.current ? :today : :later
        )
        task.sections = step.sections
        task
      end
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
          You are the goal-planning feature of a private, self-hosted life assistant.
          The user names something they want to accomplish; you break it into concrete
          steps so they always know the next small thing to do. Respond with a JSON object:
          {"sections": ["slug", ...],
           "target_on": "YYYY-MM-DD" or null,
           "steps": [{"title": "...", "notes": "..." or null,
                      "due_on": "YYYY-MM-DD" or null, "sections": ["slug", ...],
                      "questions": ["...", ...]}, ...]}.
          Steps must be small concrete actions completable within a single day, each
          with a clear done/not-done outcome, listed in the order they should happen.
          Use 3 to #{MAX_STEPS} steps for a substantial goal; a trivial goal may need only one.
          Spread due_on dates at a sustainable pace — a step or two per day — starting
          today and finishing by the target date when there is one.
          If existing steps are listed, propose only steps that are missing; never
          repeat or rephrase one that already exists.
          Choose sections only from the provided list, at most #{MAX_SECTIONS} for the goal and
          for each step, ordered by relevance; choose none if nothing clearly fits.
          Set target_on only when the goal states or clearly implies a deadline
          ("by December", "before the lease ends in June"), resolved against today's
          date; otherwise use null.
          For each step that is mental work an assistant could help with in
          conversation — deciding, brainstorming, drafting, planning, researching —
          give one or two short opening questions, posed directly to the user, that
          would move that step toward an answer. Use an empty questions array for
          physical errands a conversation wouldn't help with.
        PROMPT
      end

      def user_prompt
        parts = [ "Today's date: #{Date.current.iso8601} (#{Date.current.strftime("%A")})" ]
        parts << "Goal: #{@goal.title}"
        parts << "Description: #{@goal.description}" if @goal.description.present?
        parts << "Target date: #{@goal.target_on.iso8601}" if @goal.target_on
        parts << "Framing from the tool that captured this goal:\n#{@brief}" if @brief.present?
        if @goal.tasks.any?
          listing = @goal.tasks.map { |task| "- #{task.title}#{" (done)" if task.completed?}" }.join("\n")
          parts << "Existing steps:\n#{listing}"
        end
        parts << "Available sections (slug — meaning):\n#{Llm::Taxonomy.listing}"
        parts.join("\n\n")
      end

      def parsed_steps(steps)
        Array(steps).first(MAX_STEPS).filter_map do |step|
          next unless step.is_a?(Hash) && step["title"].present?

          Step.new(
            title: step["title"].to_s,
            notes: step["notes"].is_a?(String) ? step["notes"].presence : nil,
            due_on: parsed_date(step["due_on"]),
            sections: Llm::Taxonomy.match(step["sections"], limit: MAX_SECTIONS),
            questions: Array(step["questions"]).grep(String).map(&:strip).reject(&:empty?).first(MAX_QUESTIONS)
          )
        end
      end

      def parsed_date(value)
        return nil if value.blank?

        Date.iso8601(value.to_s)
      rescue Date::Error
        nil
      end
  end
end
