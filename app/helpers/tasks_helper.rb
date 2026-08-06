module TasksHelper
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
