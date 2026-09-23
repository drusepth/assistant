module TasksHelper
  # What a due date says at a glance. "Due Aug 8" is a subtraction you have
  # to perform in the middle of a list, and the answer — how late this is —
  # is the whole reason you looked. So a date near today speaks in days:
  # a week either side reads in words, everything beyond it as a date.
  # A finished task keeps the plain date; "9 days late" is no longer news.
  def task_due_label(task)
    return nil if task.due_on.blank?

    days = (task.due_on - Date.current).to_i
    plain = "Due #{task.due_on.strftime("%b %-d")}"
    return plain if task.completed?

    case days
    when 0 then "Due today"
    when 1 then "Due tomorrow"
    when -1 then "1 day late"
    when 2..6 then "Due #{task.due_on.strftime("%A")}"
    else days.negative? ? "#{-days} days late" : plain
    end
  end

  def quick_add_placeholder
    if auto_sort_enabled?
      "What needs doing? Just type it — sections and due dates get sorted for you."
    else
      "What needs doing?"
    end
  end

  def task_auto_sort_hint
    if auto_sort_enabled?
      "Just write it down — your assistant files it into sections and picks up any due date you mention."
    else
      "Sections can be added after saving, from the task's edit page."
    end
  end

  # "Mon, Wed, Fri", "Every day", "Every 2 weeks · Thu" — the short form of
  # a repeat, for a chip on a row.
  def repeat_label(rule)
    days = rule.weekdays.sort_by { |code| Recurrence::Rule::WEEKDAYS[code] }
      .map { |code| Recurrence::Rule::DAY_NAMES[code].first(3) }.join(", ")

    case Reminder.repeat_key_for(rule)
    when "daily" then "Every day"
    when "weekdays" then "Weekdays"
    when "weekly" then days.presence || "Weekly"
    when "biweekly" then [ "Every 2 weeks", days.presence ].compact.join(" · ")
    when "monthly" then "Monthly"
    when "yearly" then "Yearly"
    else rule.describe.to_s.upcase_first
    end
  end

  # "16:00" → "4 PM", "08:30" → "8:30 AM".
  def clock_label(time_of_day)
    hour, minute = time_of_day.to_s.split(":").map(&:to_i)
    Time.utc(2000, 1, 1, hour.to_i, minute.to_i).strftime("%-l:%M %p").sub(":00", "")
  end
end
