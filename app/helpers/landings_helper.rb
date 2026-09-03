# The review page's inputs (D-landing-registry): one input per declared
# field, chosen by the field's type, through the app's form builder — so a
# kind never writes a form partial and an edited value is checked by the
# same code that checked the proposed one.
module LandingsHelper
  def landing_field(form, field, context)
    label = field.name.humanize
    case field.type
    when :text
      form.field(field.name, as: :text_area, label_text: label, rows: 3)
    when :date
      form.field(field.name, label_text: label) do
        render "shared/date_shortcuts_field", form: form, method: field.name.to_sym, required: field.required?
      end
    when :time
      form.field(field.name, as: :time_field, label_text: label)
    when :decimal, :integer
      form.field(field.name, as: :number_field, label_text: label, step: field.type == :integer ? 1 : "any")
    when :choice
      form.field(field.name, label_text: label) do
        form.select(field.name, field.options(context), { include_blank: field.required? ? false : "—" })
      end
    when :ref
      form.field(field.name, label_text: label) do
        form.select(field.name, context.ref_options(field.ref), { include_blank: field.required? ? false : "—" })
      end
    else
      form.field(field.name, label_text: label, required: field.required?)
    end
  end

  # The chip that says what a landing becomes: "calendar · 12 Aug 2026".
  def landing_chip_text(draft, context)
    preview = draft.landing_class.new(context).preview(draft.attributes)
    date = preview.date && (Date.iso8601(preview.date).strftime("%-d %b %Y") rescue nil)
    [ landing_kind_label(draft.kind), date ].compact.join(" · ")
  end

  def landing_kind_label(kind)
    { "event" => "calendar" }.fetch(kind) { Landing.find!(kind).label }
  end
end
