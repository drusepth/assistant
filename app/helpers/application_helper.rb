module ApplicationHelper
  # Is there a model behind the AI features on this page at all? Features
  # that would otherwise guess are off without one, and say so (CLAUDE.md's
  # standing rule), so views ask this before offering them.
  def model_configured?
    Current.user.household.model_profile&.configured?
  end

  alias_method :auto_sort_enabled?, :model_configured?

  # The page the user is looking at, for a link's return_to — so the form it
  # opens sends Cancel and Save back here. A row re-rendered by a verb's
  # turbo stream is drawn during a PATCH, whose own path is no page at all,
  # so there the page is the one the verb was pressed on (the referer).
  def current_page_path
    return request.fullpath if request.get?

    uri = URI.parse(request.referer.to_s)
    uri.request_uri if uri.host == request.host && uri.path.present?
  rescue URI::InvalidURIError
    nil
  end

  # What shared/_section_picker offers: the sections this user actually
  # switched on (D4) plus their subsections, and anything already applied so
  # a tag the picker wouldn't otherwise list can't be dropped by saving the
  # form. A household that turned Rights off shouldn't be asked whether its
  # dinner is about voting.
  #
  # A pet's lens is household-wide but the pet behind it is private (D9), so
  # the lenses of pets this user can't see are left out: another member's
  # private cat is not a tag you should be offered.
  def section_picker_choices(item)
    enabled_ids = Current.user.enabled_sections.map(&:id)
    unseen_pet_lenses = Pet.where.not(id: Pet.visible_to(Current.user).select(:id)).select(:section_id)

    Section.where(id: enabled_ids + item.section_ids)
      .or(Section.where(parent_id: enabled_ids).where.not(id: unseen_pet_lenses))
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
