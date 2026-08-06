module Tool
  # Declarative superclass for tool definitions. A subclass names itself for
  # the Act zone (title/description), registers on section slugs, declares
  # the minimal inputs its form asks for (D16: only what can't be read from
  # owned data), and implements the LLM round-trip.
  #
  # Draft tools (kind :draft) share one response contract — DRAFT_FORMAT —
  # and the default `handle` lands it: a draft Note plus up to MAX_FOLLOW_UPS
  # follow-up Tasks, all filed under `filing`. A draft tool usually only
  # writes `messages` and overrides `filing`/`fallback_title` when the
  # defaults aren't right.
  #
  # Plan tools (kind :plan) override `call` with one line: `plan_goal!` —
  # goal capture with framing, riding the same Goals::BreakDown pipeline as
  # every goal. No tool adds schema or pipeline of its own.
  class Base
    Input = Data.define(:name, :label, :kind, :required, :hint) do
      def required? = required
      def document? = kind == :document
      def person? = kind == :person
    end

    class_attribute :title, :description, :kind, instance_accessor: false, default: nil
    class_attribute :section_slugs, instance_accessor: false, default: []
    class_attribute :input_definitions, instance_accessor: false, default: []

    MAX_FOLLOW_UPS = 3

    DRAFT_FORMAT = <<~PROMPT.freeze
      Respond with a JSON object:
      {"draft": {"title": "...", "body": "..."},
       "follow_ups": [{"title": "...", "due_on": "YYYY-MM-DD" or null}, ...]}.
      follow_ups are at most #{MAX_FOLLOW_UPS} small concrete actions, each completable
      within a single day; set due_on only when a real deadline is stated or
      clearly implied, resolved against today's date.
      Invent nothing — where a detail is unknown, leave a [BRACKETED
      PLACEHOLDER] for the user to fill in.
    PROMPT

    class << self
      def slug = name.demodulize.underscore

      def input(name, label:, kind: :text, required: false, hint: nil)
        self.input_definitions += [ Input.new(name: name.to_s, label:, kind:, required:, hint:) ]
      end

      def inputs = input_definitions

      def section_records = Section.where(slug: section_slugs).order(:parent_id, :position)
    end

    def initialize(run)
      @run = run
      @user = run.user
    end

    # The template method ToolRunJob calls. Everything user-facing that can
    # go wrong raises Llm::Error so the run fails with a friendly message.
    def call
      handle(profile.client.chat(messages, json: true))
    end

    private
      attr_reader :run, :user

      # Default landing for the DRAFT_FORMAT contract.
      def handle(response)
        body = response.dig("draft", "body")
        raise Llm::Error, "The model didn't return a draft — try again." if body.blank?

        note = record(user.notes.create!(
          title: response.dig("draft", "title").presence || fallback_title, body: body
        ))
        note.sections = filing

        Array(response["follow_ups"]).first(MAX_FOLLOW_UPS).each do |step|
          next unless step.is_a?(Hash) && step["title"].present?

          due_on = parsed_date(step["due_on"])
          task = record(user.tasks.create!(
            title: step["title"].to_s, due_on: due_on,
            bucket: due_on && due_on <= Date.current ? :today : :later
          ))
          task.sections = filing
        end
      end

      # Where a draft tool's output is filed. Default: where the tool lives.
      def filing = self.class.section_records

      def fallback_title = "#{self.class.title} — draft"

      # The whole plan-tool contract: create a plain Goal, hand it to the
      # shared breakdown pipeline with framing, record what comes back.
      def plan_goal!(title:, brief:, description: nil)
        goal = record(user.goals.create!(title: title, description: description))
        begin
          Goals::BreakDown.new(goal: goal, profile: profile, brief: brief).plan!.each { |task| record(task) }
          # The plan is always findable where the tool lives, on top of
          # whatever the model filed it under.
          goal.sections = (goal.sections.to_a + self.class.section_records).uniq
        ensure
          # Stamp even on failure so the goal card can't spin forever — a
          # failed run leaves an ordinary unplanned goal the user can retry
          # from its own page, and the board refreshes either way.
          goal.update_column(:broken_down_at, Time.current)
          Turbo::StreamsChannel.broadcast_refresh_to(user, :tasks)
        end
        goal
      end

      def profile
        profile = user.household.model_profile
        unless profile&.configured?
          raise Llm::Error, "Tools need an AI model — ask your household admin to configure one in Settings."
        end
        profile
      end

      def inputs = run.inputs.with_indifferent_access

      # Created primitives are recorded on the run so its page can show them.
      def record(item)
        run.tool_run_items.create!(item: item)
        item
      end

      def parsed_date(value)
        return nil if value.blank?

        Date.iso8601(value.to_s)
      rescue Date::Error
        nil
      end
  end
end
