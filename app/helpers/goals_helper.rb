module GoalsHelper
  def goal_capture_placeholder
    if auto_sort_enabled?
      "What do you want to accomplish? Your assistant breaks it into steps."
    else
      "What do you want to accomplish?"
    end
  end

  # Momentum, for goals with no finish line (D-goal-shape): honest across
  # re-plans, never a verdict on an open-ended aspiration.
  def goal_momentum(goal)
    count = goal.steps_this_week
    return "#{count} #{"step".pluralize(count)} this week" if count.positive?
    return "Last progress #{time_ago_in_words(goal.last_progress_at)} ago" if goal.last_progress_at

    "No progress yet"
  end

  # Said gently on purpose (D-goal-pause): information, not a red badge.
  def goal_stale_label(goal)
    "Quiet for #{time_ago_in_words(goal.last_activity_at)}"
  end

  def goal_auto_sort_hint
    if auto_sort_enabled?
      "Just name the outcome — your assistant breaks it into day-sized steps, schedules them, and files everything into sections."
    else
      "Steps can be added from the goal's page; a description and target date from its edit page."
    end
  end
end
