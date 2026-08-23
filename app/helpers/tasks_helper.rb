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
      "Details like sections and due dates can be added after saving, from the task's edit page."
    end
  end
end
