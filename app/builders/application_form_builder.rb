# Default form builder app-wide (set in ApplicationController). Every input
# helper picks up the design system's atoms, and `field` renders the standard
# label + control + errors stack — restyle forms here, once.
class ApplicationFormBuilder < ActionView::Helpers::FormBuilder
  TEXTUAL_HELPERS = %i[
    text_field email_field password_field url_field telephone_field
    number_field date_field datetime_local_field time_field search_field
  ].freeze

  TEXTUAL_HELPERS.each do |helper|
    define_method(helper) do |method, options = {}|
      super(method, merge_classes(options, "input"))
    end
  end

  def text_area(method, options = {})
    super(method, merge_classes({ rows: 4 }.merge(options), "input"))
  end

  def select(method, choices = nil, options = {}, html_options = {}, &block)
    super(method, choices, options, merge_classes(html_options, "input"), &block)
  end

  def collection_select(method, collection, value_method, text_method, options = {}, html_options = {})
    super(method, collection, value_method, text_method, options, merge_classes(html_options, "input"))
  end

  def file_field(method, options = {})
    super(method, merge_classes(options, "block w-full text-sm text-soft file:mr-3 file:btn file:btn-secondary file:btn-sm"))
  end

  def check_box(method, options = {}, checked_value = "1", unchecked_value = "0")
    super(method, merge_classes(options, "size-4 rounded accent-primary-600"), checked_value, unchecked_value)
  end

  def label(method, text = nil, options = {}, &block)
    super(method, text, merge_classes(options, "label"), &block)
  end

  def submit(value = nil, options = {})
    super(value, merge_classes(options, "btn btn-primary"))
  end

  # Standard field stack: label + control + hint + errors. Pass a block for
  # controls that need custom arguments (selects, checkboxes, pickers).
  def field(method, as: :text_field, label_text: nil, hint: nil, **options, &block)
    control = block ? @template.capture(&block) : public_send(as, method, **options)

    @template.tag.div(class: "space-y-1") do
      @template.safe_join([
        label(method, label_text),
        control,
        hint ? @template.tag.p(hint, class: "hint") : nil,
        errors_for(method)
      ].compact)
    end
  end

  def errors_for(method)
    messages = object&.errors&.full_messages_for(method)
    return if messages.blank?

    @template.tag.p(messages.to_sentence, class: "field-error")
  end

  private
    def merge_classes(options, classes)
      options.merge(class: [ classes, options[:class] ].compact.join(" "))
    end
end
