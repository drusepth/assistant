module ApplicationHelper
  def auto_sort_enabled?
    Current.user.household.model_profile&.configured?
  end

  # What shared/_section_picker offers: the sections this user actually
  # switched on (D4) plus their subsections, and anything already applied so
  # a tag the picker wouldn't otherwise list can't be dropped by saving the
  # form. A household that turned Rights off shouldn't be asked whether its
  # dinner is about voting.
  def section_picker_choices(item)
    enabled_ids = Current.user.enabled_sections.map(&:id)

    Section.where(id: enabled_ids + item.section_ids)
      .or(Section.where(parent_id: enabled_ids))
      .order(:parent_id, :position)
  end

  # The state of the filing on the closed Advanced line: what this item is
  # filed under, or who is going to file it. Folding the picker away should
  # never mean you can't tell.
  def section_filing_hint(item)
    return "filed under #{item.sections.map(&:qualified_name).to_sentence}" if item.sections.any?
    return "your assistant files this one" if item.is_a?(AutoSortable) && auto_sort_enabled?

    "not filed yet"
  end

  # The celebration waiting in the flash (D-task-celebration), or nil. Parsed
  # here rather than in the partial so a flash left over from an older
  # release — or anything else that isn't the JSON we wrote — is simply no
  # party, never a 500 on an unrelated page.
  def celebration
    raw = flash[:celebrate]
    return nil if raw.blank?

    parsed = JSON.parse(raw)
    parsed.is_a?(Hash) && parsed["token"].present? ? parsed : nil
  rescue JSON::ParserError
    nil
  end

  # Quick-pick chips for date fields (shared/_date_shortcuts_field).
  def date_shortcuts
    today = Date.current
    {
      "Yesterday" => today.yesterday,
      "Today" => today,
      "Tomorrow" => today.tomorrow,
      "Next week" => today.next_week,
      "Next month" => today.next_month
    }
  end
end
