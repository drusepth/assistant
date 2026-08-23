module ApplicationHelper
  def auto_sort_enabled?
    Current.user.household.model_profile&.configured?
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
