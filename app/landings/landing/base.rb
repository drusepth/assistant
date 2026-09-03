module Landing
  # Declarative superclass for landing kinds (D-landing-registry). A kind
  # names itself for the prompt (`description`), says which owned primitive
  # it writes (`produces`, an export key the registry test reads), declares
  # its fields, and implements `land!`. Everything else — the prompt line,
  # coercion and validation, the fingerprint, the preview, the form — is
  # derived from the field list here, once.
  #
  # Two validation entry points, one set of rules. `validate` is the model
  # path: it drops what doesn't parse and drops the whole entry when a
  # required field is missing, because a model's answer is a proposal and a
  # short proposal beats a wrong one. `coerce` is the form path: it keeps
  # every error, so a person who typed a bad date sees it on the field.
  class Base
    Field = Data.define(:name, :hint, :type, :required, :choices, :ref, :limit) do
      def required? = required
      def ref? = type == :ref
      def choice? = type == :choice
      def multiline? = type == :text

      # The closed set for a choice field, as [label, value] pairs. A lambda
      # takes the context (a pet's care kinds depend on the pet); a literal
      # array stands alone.
      def options(context)
        list = choices.respond_to?(:call) ? choices.call(context) : choices
        Array(list).map { |option| option.is_a?(Array) ? option : [ option.to_s.humanize, option.to_s ] }
      end
    end

    Preview = Data.define(:kind, :title, :detail, :date)

    class_attribute :description, :produces, instance_accessor: false, default: nil
    # An amendment kind updates a row the ref names instead of creating one;
    # the review card shows its preview's old → new lines.
    class_attribute :amends, instance_accessor: false, default: false
    class_attribute :field_definitions, instance_accessor: false, default: []

    class << self
      def kind = name.demodulize.underscore

      # types: :string, :text, :date, :time, :decimal, :integer, :choice, :ref
      def field(name, hint = nil, type: :string, required: false, choices: nil, ref: nil, limit: nil)
        limit ||= type == :text ? 5_000 : 200
        self.field_definitions += [ Field.new(name: name.to_s, hint:, type:, required:, choices:, ref:, limit:) ]
      end

      def fields = field_definitions
      def field_named(name) = fields.find { |field| field.name == name.to_s }

      # One line of the generated prompt block: what the kind is, then each
      # field with its hint, its closed set where it has one, and whether
      # it is required.
      def prompt_line(context)
        described = fields.map do |field|
          notes = [ field.hint ]
          notes << "YYYY-MM-DD" if field.type == :date && field.hint.to_s.exclude?("YYYY")
          notes << "HH:MM" if field.type == :time && field.hint.to_s.exclude?("HH")
          notes << "a number" if %i[ decimal integer ].include?(field.type)
          notes << "one of: #{field.options(context).map(&:last).join(", ")}" if field.choice?
          notes << "one of the #{field.ref.to_s.pluralize} listed below, by its key" if field.ref?
          notes << "required" if field.required?
          notes.compact!
          notes.any? ? "#{field.name} (#{notes.join("; ")})" : field.name
        end
        "- #{kind} — #{description}. Fields: #{described.join(", ")}."
      end

      # The one-line version, for the presence pass (INTAKE_PLAN §3): the
      # name and what it is, none of the fields.
      def name_line = "- #{kind} — #{description}"

      # Label for chips and previews: "calendar", "task", "contact".
      def label = kind.humanize.downcase
    end

    def initialize(context)
      @context = context
    end

    attr_reader :context

    def kind = self.class.kind
    def fields = self.class.fields

    # Model path (see class comment): attributes or nil.
    def validate(raw)
      draft = coerce(raw, lenient: true)
      draft.valid? ? draft.attributes : nil
    end

    # Form path: a Draft carrying attributes and every error.
    def coerce(raw, lenient: false)
      # A plain hash either way by here — the model's parsed JSON, or params
      # the controller already permitted against this kind's own fields.
      raw = raw.to_h.stringify_keys
      draft = Draft.new(kind: kind)

      fields.each do |field|
        value = raw[field.name]
        value = value.to_s.strip if value.is_a?(String)
        if value.blank?
          draft.errors.add(field.name, "is required") if field.required?
          next
        end

        cleaned, error = cast(field, value)
        if error
          # A model's malformed optional field is dropped; a required one
          # sinks the entry. A person's is always shown.
          draft.errors.add(field.name, error) if !lenient || field.required?
        else
          draft.attributes[field.name] = cleaned
        end
      end

      draft
    end

    # The write. Subclasses return the row they made; `sections` is the
    # filing it gets (the document's, plus whatever the kind adds).
    def land!(attributes, sections:)
      raise NotImplementedError
    end

    # Enough of the attributes to recognize the same fact twice: the model
    # proposing it on re-analysis, or two documents stating it.
    def fingerprint(attributes)
      "#{kind}:#{attributes.values_at(*key_fields).map { |value| value.to_s.parameterize }.join(":")}"
    end

    # A row this user can already see that says the same thing, or nil.
    # Deterministic and narrow: the review page flags it and leaves the box
    # unchecked; it never decides.
    def duplicate_of(attributes) = nil

    def preview(attributes)
      Preview.new(kind: kind, title: attributes["title"].to_s, detail: nil, date: attributes["on"] || attributes["due_on"])
    end

    # Sections every row of this kind gets on top of the document's filing
    # (a medication is Health wherever the document was filed).
    def default_sections = []

    private
      def key_fields = %w[ title ]
      def user = context.user

      def cast(field, value)
        case field.type
        when :string then [ value.to_s.squish.truncate(field.limit), nil ]
        when :text then [ value.to_s.strip.truncate(field.limit), nil ]
        when :date
          date = Date.iso8601(value.to_s) rescue nil
          date ? [ date.iso8601, nil ] : [ nil, "isn't a date (use YYYY-MM-DD)" ]
        when :time
          hour, minute = value.to_s.match(/\A(\d{1,2}):(\d{2})\z/)&.captures
          hour && hour.to_i < 24 && minute.to_i < 60 ? [ format("%02d:%02d", hour.to_i, minute.to_i), nil ] : [ nil, "isn't a time (use HH:MM)" ]
        when :decimal
          number = value.to_s.delete(",").match(/-?\d+(\.\d+)?/)&.[](0)
          number ? [ number, nil ] : [ nil, "isn't a number" ]
        when :integer
          number = value.to_s.delete(",").match(/-?\d+/)&.[](0)
          number ? [ number.to_i, nil ] : [ nil, "isn't a whole number" ]
        when :choice
          allowed = field.options(context).map(&:last)
          allowed.include?(value.to_s) ? [ value.to_s, nil ] : [ nil, "isn't one of the options" ]
        when :ref
          context.resolve(field.ref, value) ? [ value.to_s, nil ] : [ nil, "isn't one of your #{field.ref.to_s.pluralize}" ]
        else
          [ value.to_s, nil ]
        end
      end

      def parsed_date(value)
        Date.iso8601(value.to_s) if value.present?
      rescue Date::Error
        nil
      end

      def tag(record, sections)
        record.sections = (Array(sections) + default_sections).uniq if record.respond_to?(:sections=)
        record
      end

      # A landing about a pet is filed under her lens — "about Rex" is a tag
      # (D-pet-primitive), so the pet page and everything-about-Rex see it.
      def with_pet(sections, attributes)
        pet = attributes["pet"].present? && context.resolve(:pet, attributes["pet"])
        pet ? (Array(sections) + [ pet.section ]).uniq : Array(sections)
      end
  end
end
