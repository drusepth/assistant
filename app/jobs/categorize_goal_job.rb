class CategorizeGoalJob < ApplicationJob
  queue_as :default

  def perform(goal)
    profile = goal.auto_sort_profile
    return unless profile
    return if goal.sections.any? # the user tagged it themselves — don't second-guess

    result = Goals::Categorize.new(goal: goal, profile: profile).call
    goal.sections = result.sections
    goal.update!(target_on: result.target_on) if goal.target_on.nil? && result.target_on
  rescue Llm::Error
    # Best-effort: an unreachable or misbehaving model just leaves the goal
    # unsorted, and the user can tag it from the edit form.
  end
end
