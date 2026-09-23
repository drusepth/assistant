# Default form builder app-wide (set in ApplicationController). Every input
# helper picks up the design system's atoms, and `field` renders the standard
# label + control + errors stack — restyle forms here, once.
class ApplicationFormBuilder < ActionView::Helpers::FormBuilder
  TEXTUAL_HELPERS = %i[
    text_field email_field password_field url_field
    number_field date_field datetime_local_field time_field search_field
  ].freeze

  TEXTUAL_HELPERS.each do |helper|
    define_method(helper) do |method, options = {}|
      super(method, merge_classes(options, "input"))
    end
  end

  # Every phone box in the app is this one: the value shows in the printed
  # shape rather than the stored E.164 (PhoneNumber), the Stimulus mask
  # formats it as it's typed, and the pattern stops a half-typed number at
  # the browser. The server normalizes whatever arrives, so a form that
  # never ran the JavaScript still saves the same thing.
  def telephone_field(method, options = {})
    saved = object.try(method)
    options = {
      value: PhoneNumber.format(saved),
      placeholder: "(555) 555-0142",
      autocomplete: "tel",
      inputmode: "tel",
      title: "A 10-digit number like (555) 555-0142. Outside the US or Canada? Start with + and the country code."
    }.merge(options)
    # A number saved before the mask, or imported in a shape PhoneNumber
    # wouldn't guess at ("555-1234"), is left submittable: editing a
    # contact's birthday shouldn't be blocked on a phone number nobody
    # touched. Retyping it runs the mask like any other.
    options[:pattern] ||= PHONE_PATTERN if saved.blank? || saved.to_s.start_with?("+")
    options[:data] = { controller: "phone-input", action: "input->phone-input#format" }.merge(options[:data] || {})

    super(method, merge_classes(options, "input tabular-nums"))
  end
  alias_method :phone_field, :telephone_field

  # What the mask produces: a complete North American number, or a "+" and
  # up to fifteen digits. Escaped for the `v` flag browsers compile
  # `pattern` with, where a bare "(" inside a class is a syntax error.
  PHONE_PATTERN = '\(\d{3}\) \d{3}-\d{4}|\+[\d \(\)\-]{8,24}'.freeze

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
    accept_hint = options[:accept]

    input_data = (options[:data] || {}).merge(
      file_input_target: "input",
      action: "change->file-input#updateState"
    )

    input_options = options.merge(
      class: [ "absolute inset-0 opacity-0 w-full h-full cursor-pointer z-10", options[:class] ].compact.join(" "),
      data: input_data
    )

    input_html = super(method, input_options)

    @template.content_tag(:div,
      class: "file-input-dropzone group",
      data: {
        controller: "file-input",
        action: "dragover->file-input#dragOver dragleave->file-input#dragLeave drop->file-input#drop"
      }
    ) do
      @template.safe_join([
        input_html,
        @template.content_tag(:div, class: "flex flex-col items-center justify-center gap-1.5 pointer-events-none", data: { file_input_target: "idle" }) do
          @template.safe_join([
            @template.tag.svg(
              @template.tag.path(
                d: "M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12",
                stroke: "currentColor", stroke_width: "2", stroke_linecap: "round", stroke_linejoin: "round"
              ),
              xmlns: "http://www.w3.org/2000/svg", fill: "none", viewBox: "0 0 24 24", class: "size-8 text-primary-600 group-hover:scale-110 transition-transform duration-150"
            ),
            @template.content_tag(:p, class: "text-sm text-ink") do
              @template.safe_join([
                @template.content_tag(:span, "Click to choose a file", class: "font-semibold text-primary-700 underline decoration-primary-300 decoration-2 underline-offset-2 group-hover:decoration-primary-600"),
                " or drag & drop here"
              ])
            end,
            accept_hint ? @template.content_tag(:p, "Accepted formats: #{accept_hint}", class: "text-xs font-medium text-soft max-w-full text-balance") : nil
          ].compact)
        end,
        @template.content_tag(:div, class: "hidden flex-col items-center justify-center gap-1.5 pointer-events-none", data: { file_input_target: "selected" }) do
          @template.safe_join([
            @template.content_tag(:div, class: "flex items-center justify-center size-9 rounded-full bg-primary-100 text-primary-700 mb-0.5") do
              @template.tag.svg(
                @template.tag.path(
                  d: "M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z",
                  stroke: "currentColor", stroke_width: "2", stroke_linecap: "round", stroke_linejoin: "round"
                ),
                xmlns: "http://www.w3.org/2000/svg", fill: "none", viewBox: "0 0 24 24", class: "size-6"
              )
            end,
            @template.content_tag(:div, class: "flex items-center gap-2 max-w-full px-3 py-1 rounded-lg bg-surface border border-edge shadow-xs") do
              @template.safe_join([
                @template.tag.svg(
                  @template.tag.path(
                    d: "M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z",
                    stroke: "currentColor", stroke_width: "2", stroke_linecap: "round", stroke_linejoin: "round"
                  ),
                  xmlns: "http://www.w3.org/2000/svg", fill: "none", viewBox: "0 0 24 24", class: "size-4 text-primary-600 shrink-0"
                ),
                @template.content_tag(:span, "", class: "text-sm font-semibold text-ink truncate max-w-[200px] sm:max-w-xs", data: { file_input_target: "filename" }),
                @template.content_tag(:span, "", class: "text-xs font-normal text-soft shrink-0", data: { file_input_target: "filesize" })
              ])
            end,
            @template.content_tag(:p, "Click or drop a new file to replace", class: "text-xs text-soft font-medium")
          ])
        end
      ])
    end
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
