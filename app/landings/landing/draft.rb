module Landing
  # One landing as the review page holds it (D-document-intake): its kind,
  # its attributes (the model's, or the user's edits), and any errors the
  # kind's coercion raised. Shaped for `fields_for` — every declared field
  # reads as a method, and `errors` is a real ActiveModel::Errors so the
  # app's form builder renders them the way it renders a model's.
  class Draft
    extend ActiveModel::Naming
    extend ActiveModel::Translation

    def self.model_name = ActiveModel::Name.new(self, nil, "Landing")

    attr_reader :kind, :attributes, :errors
    attr_accessor :index, :keep, :fingerprint, :status, :flags

    def initialize(kind:, attributes: {}, index: nil, keep: true, fingerprint: nil, status: "proposed", flags: [])
      @kind = kind
      @attributes = attributes.to_h.stringify_keys
      @errors = ActiveModel::Errors.new(self)
      @index = index
      @keep = keep
      @fingerprint = fingerprint
      @status = status
      @flags = flags
    end

    def valid? = errors.empty?
    def keep? = keep
    def duplicate? = flags.include?("duplicate")

    def landing_class = Landing.find!(kind)

    # ActiveModel::Errors reads values through this.
    def read_attribute_for_validation(name) = attributes[name.to_s]

    def method_missing(name, *args)
      return attributes[name.to_s] if args.empty? && landing_class.field_named(name)

      super
    end

    def respond_to_missing?(name, include_private = false)
      landing_class.field_named(name) ? true : super
    end
  end
end
