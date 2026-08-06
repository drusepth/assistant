module Tool
  # Declarative superclass for tool definitions. A subclass names itself for
  # the Act zone (title/description), registers on section slugs, declares
  # the minimal inputs its form asks for (D16: only what can't be read from
  # owned data), and implements the LLM round-trip: `messages` builds the
  # call from inputs + owned context, `handle` lands the response as draft
  # primitives recorded on the run.
  class Base
    Input = Data.define(:name, :label, :kind, :required, :hint) do
      def required? = required
      def document? = kind == :document
    end

    class_attribute :title, :description, :kind, instance_accessor: false, default: nil
    class_attribute :section_slugs, instance_accessor: false, default: []
    class_attribute :input_definitions, instance_accessor: false, default: []

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

      def parsed_date(value)
        return nil if value.blank?

        Date.iso8601(value.to_s)
      rescue Date::Error
        nil
      end
  end
end
