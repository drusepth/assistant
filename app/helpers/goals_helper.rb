module GoalsHelper
  def goal_auto_sort_hint
    if auto_sort_enabled?
      "Just name it — your assistant files it into sections and picks up any target date you mention."
    else
      "Details like a description, target date, and sections can be added after saving, from the goal's edit page."
    end
  end
end
