class CategorizeTaskJob < ApplicationJob
  include RetriesModelCalls

  queue_as :default

  def perform(task)
    profile = task.auto_sort_profile
    return unless profile
    return if task.sections.any? # the user tagged it themselves — don't second-guess

    result = Tasks::Categorize.new(task: task, profile: profile).call
    task.sections = result.sections
    updates = {}
    updates[:due_on] = result.due_on if task.due_on.nil? && result.due_on
    # The same call also seeds the task-page conversation (D30) — questions
    # only land for think-y tasks; errands keep the stock opener.
    updates[:guiding_questions] = result.questions if result.questions.any?
    task.update!(updates) if updates.any?
  rescue Llm::Error => e
    raise if will_retry?(e)

    # Auto-sorting is best-effort: once the model is out of chances the task
    # just stays unsorted, and the user can tag it from the edit form.
    # Quiet for the user, logged for whoever runs the box (/admin).
    record_failure(e, user: task.user, context: { task_id: task.id })
  end
end
