module Tool
  # Declarative superclass for tool definitions. A subclass names itself for
  # the Act zone (title/description), registers on section slugs, declares
  # the minimal inputs its form asks for (D16: only what can't be read from
  # owned data), and implements the LLM round-trip: `messages` builds the
  # call from inputs + owned context, `handle` lands the response as draft
  # primitives recorded on the run.
  class Base
    Input = Data.define(:name, :label, :kind, :required, :hint, :options) do
      def required? = required
      def document? = kind == :document
      def select? = kind == :select
      def checkboxes? = kind == :checkboxes
    end

    class_attribute :title, :description, :kind, instance_accessor: false, default: nil
    class_attribute :section_slugs, instance_accessor: false, default: []
    class_attribute :input_definitions, instance_accessor: false, default: []

    MAX_DOCUMENT_CHARS = 15_000
    MAX_FOLLOW_UPS = 3
    MAX_DEADLINES = 3
    MAX_NEXT_TOOLS = 2

    class << self
      def slug = name.demodulize.underscore

      def input(name, label:, kind: :text, required: false, hint: nil, options: nil)
        self.input_definitions += [ Input.new(name: name.to_s, label:, kind:, required:, hint:, options:) ]
      end

      def inputs = input_definitions

      def section_records = Section.where(slug: section_slugs).order(:parent_id, :position)
    end

    def initialize(run)
      @run = run
      @user = run.user
    end

    # The template method ToolRunJob calls: one JSON chat call, then the
    # subclass lands the result. Everything user-facing that can go wrong
    # raises Llm::Error so the run fails with a friendly message.
    def call
      handle(profile.client.chat(messages, json: true))
    end

    private
      attr_reader :run, :user

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

      # ── Owned context ──────────────────────────────────────────────────

      # The document an input points at, read through the visibility wall.
      # A blank input returns nil (for tools where the document is optional);
      # a chosen document that vanished or was unshared raises, because the
      # user picked it and silence would draft a letter about nothing.
      def chosen_document(input_name = :document_id)
        return nil if inputs[input_name].blank?

        (@chosen_documents ||= {})[input_name.to_s] ||=
          Document.visible_to(user).find_by(id: inputs[input_name]) ||
            raise(Llm::Error, "That document is gone or no longer shared with you.")
      end

      def document_text(document)
        text = document.extracted_text.presence || document.summary.presence
        raise Llm::Error, "That document has no readable text yet — open it and run Analyze first." unless text

        text.truncate(MAX_DOCUMENT_CHARS)
      end

      # Owned items in the given sections (default: where the tool lives),
      # through the visibility wall, as a budgeted prompt block.
      def section_context(slugs = self.class.section_slugs, budget: Context::DEFAULT_BUDGET)
        Context.new(user: user, section_slugs: slugs, budget: budget)
      end

      # ── Landing primitives ─────────────────────────────────────────────

      # Everything a tool creates is filed where the tool lives, plus the
      # filing of whatever owned items the run read (the DisputeLetter rule:
      # a letter about a Health-tagged bill lands in Disputes and Health).
      def filing
        @filing ||= (self.class.section_records + filing_sources.compact.flat_map(&:sections)).uniq
      end

      # Owned items whose sections the output inherits; subclasses override.
      def filing_sources = []

      def create_note(title:, body:)
        note = record(user.notes.create!(title:, body:))
        note.sections = filing
        note
      end

      def create_task(title:, due_on: nil, notes: nil)
        task = record(user.tasks.create!(
          title:, notes:, due_on:,
          bucket: due_on && due_on <= Date.current ? :today : :later
        ))
        task.sections = filing
        task
      end

      # Deadlines land as all-day Events: a Task can be snoozed, a date on
      # the calendar is harder to lose — and it surfaces in Calendar/Today
      # like everything else.
      def create_event(title:, on:, description: nil)
        event = record(user.events.create!(
          title:, description:, starts_at: on.in_time_zone, all_day: true
        ))
        event.sections = filing
        event
      end

      # The response-shape parsers shared by the draft-tool family: arrays
      # of {"title", "due_on"/"date"} hashes, malformed entries dropped.
      def create_follow_ups(steps, limit: MAX_FOLLOW_UPS)
        Array(steps).first(limit).each do |step|
          next unless step.is_a?(Hash) && step["title"].present?

          create_task(title: step["title"].to_s, due_on: parsed_date(step["due_on"]))
        end
      end

      def create_deadline_events(deadlines, limit: MAX_DEADLINES)
        Array(deadlines).first(limit).each do |deadline|
          next unless deadline.is_a?(Hash) && deadline["title"].present?

          date = parsed_date(deadline["date"])
          create_event(title: deadline["title"].to_s, on: date) if date
        end
      end

      # ── Routing (D21) ──────────────────────────────────────────────────

      # Tools compose by routing, never by calling each other: the model
      # proposes follow-on tools, code sanitizes — only slugs the caller
      # allows, only inputs the target declares — and the run page renders
      # what survives as prefilled next-step cards the user clicks through.
      def store_next_tools(proposals, allowed:)
        sanitized = Array(proposals).filter_map do |proposal|
          next unless proposal.is_a?(Hash)

          tool = Tool.find(proposal["slug"].to_s)
          next unless tool && tool != self.class && allowed.include?(tool.slug)

          {
            "slug" => tool.slug,
            "inputs" => sanitized_inputs(tool, proposal["inputs"]),
            "reason" => proposal["reason"].to_s.strip.presence
          }.compact
        end.uniq { |entry| entry["slug"] }.first(MAX_NEXT_TOOLS)

        run.update!(output: run.output.merge("next_tools" => sanitized)) if sanitized.any?
      end

      def sanitized_inputs(tool, inputs)
        return {} unless inputs.is_a?(Hash)

        inputs.slice(*tool.inputs.map(&:name))
          .transform_values(&:to_s)
          .reject { |_name, value| value.blank? }
      end

      # "Heading:\n- item" blocks are assembled by code so list formatting
      # never depends on model behavior.
      def bulleted_block(heading, items, limit:)
        items = Array(items).grep(String).map(&:strip).reject(&:empty?).first(limit)
        return nil if items.none?

        "#{heading}:\n#{items.map { |item| "- #{item}" }.join("\n")}"
      end

      def parsed_date(value)
        return nil if value.blank?

        Date.iso8601(value.to_s)
      rescue Date::Error
        nil
      end
  end
end
