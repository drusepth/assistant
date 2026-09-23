# Quick capture from anywhere: a + button whose minimal form (D16) opens in
# a dropdown on the page you're already on, instead of costing a page load
# to `/tasks/new` and a second one to come back.
#
#   <%= quick_add :task %>
#   <%= quick_add :task, label: "Task for today", prefill: { due_on: Date.current }, primary: true %>
#   <%= quick_add :event, label: "Add an appointment", prefill: { section_ids: [ pet.section_id ] } %>
#
# `prefill` takes the same keys the matching `new` action reads from its
# query string, so the inline form and the "Full form" link it carries
# start from the same record. Saving lands you back on the page you were on
# (`return_to`, the current path unless given).
#
# `name` must be unique among the quick-adds on one page; it defaults to the
# kind, and anything other than the kind also namespaces the form's field
# ids, so two event forms on one page don't share `id="event_title"`. Every
# other option goes to Ui::QuickAddComponent (`primary:`, `small:`,
# `tile:`, `icon:`, `align:`).
module QuickAddHelper
  QUICK_ADD_KINDS = %i[ task note event goal ].freeze

  def quick_add(kind, label: nil, title: nil, name: nil, prefill: {}, return_to: request.fullpath, **options)
    kind = kind.to_sym
    raise ArgumentError, "no quick-add for #{kind.inspect}" unless QUICK_ADD_KINDS.include?(kind)

    name = (name || kind).to_s
    record = quick_add_record(kind, prefill)
    full_form_url = public_send(:"new_#{kind}_path", prefill.merge(return_to: return_to))

    render(Ui::QuickAddComponent.new(name: name, label: label || kind.to_s.humanize,
             title: title || "New #{kind}", full_form_url: full_form_url, **options)) do
      render "#{kind.to_s.pluralize}/quick_form", kind => record, return_to: return_to,
        autofocus: false, namespace: (name unless name == kind.to_s)
    end
  end

  private
    # Mirrors each controller's `new`, so a prefill means the same thing
    # inline as it does on the page.
    def quick_add_record(kind, prefill)
      prefill = prefill.to_h.symbolize_keys
      case kind
      when :task then Current.user.tasks.new(prefill.slice(:title, :due_on, :goal_id, :section_ids))
      when :note then Current.user.notes.new(prefill.slice(:title, :body, :section_ids))
      when :event
        Current.user.events.new(prefill.slice(:title, :section_ids).merge(starts_date: prefill[:date]&.to_date))
      when :goal then Current.user.goals.new(prefill.slice(:title))
      end
    end
end
