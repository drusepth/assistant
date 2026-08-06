module ApplicationHelper
  def auto_sort_enabled?
    Current.user.household.model_profile&.configured?
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
