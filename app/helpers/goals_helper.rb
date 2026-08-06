module GoalsHelper
  def goal_capture_placeholder
    if auto_sort_enabled?
      "What do you want to accomplish? Your assistant breaks it into steps."
    else
      "What do you want to accomplish?"
    end
  end

  def goal_auto_sort_hint
    if auto_sort_enabled?
      "Just name the outcome — your assistant breaks it into day-sized steps, schedules them, and files everything into sections."
    else
      "Steps can be added from the goal's page; a description and target date from its edit page."
    end
  end
end
