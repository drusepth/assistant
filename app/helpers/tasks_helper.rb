module TasksHelper
  def quick_add_placeholder
    if Current.user.household.model_profile&.configured?
      "What needs doing? Just type it — sections and due dates get sorted for you."
    else
      "What needs doing?"
    end
  end

  def auto_sort_hint(task)
    if task.auto_sort_profile
      "Just write it down — your assistant files it into sections and picks up any due date you mention."
    else
      "Details like sections and due dates can be added after saving, from the task's edit page."
    end
  end
end
