class BreakDownGoalJob < ApplicationJob
  queue_as :default

  # append: false is the create-time breakdown and only ever fills an
  # unplanned goal; append: true is the goal page's explicit "suggest more
  # steps" and adds to an existing plan (the prompt sees current steps and
  # proposes only what's missing).
  def perform(goal, append: false)
    profile = goal.auto_sort_profile
    return unless profile
    return if goal.tasks.any? && !append

    result = Goals::BreakDown.new(goal: goal, profile: profile).call

    goal.sections = result.sections if goal.sections.none? # hand-tagged goals are left alone
    goal.update!(target_on: result.target_on) if goal.target_on.nil? && result.target_on

    result.steps.each do |step|
      task = goal.user.tasks.create!(
        goal: goal, title: step.title, notes: step.notes, due_on: step.due_on,
        bucket: step.due_on && step.due_on <= Date.current ? :today : :later
      )
      task.sections = step.sections
    end
  rescue Llm::Error
    # Best-effort (D16): an unreachable or misbehaving model leaves the goal
    # as a single unplanned item — the user can add steps by hand or retry
    # from the goal page.
  ensure
    # Stamp even on failure so the "breaking into steps…" state can't stick,
    # and refresh the owner's board either way.
    if goal&.persisted?
      goal.update_column(:broken_down_at, Time.current)
      Turbo::StreamsChannel.broadcast_refresh_to(goal.user, :tasks)
    end
  end
end
