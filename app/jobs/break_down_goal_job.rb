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

    Goals::BreakDown.new(goal: goal, profile: profile).plan!
  rescue Llm::Error => e
    # Best-effort (D16): an unreachable or misbehaving model leaves the goal
    # as a single unplanned item — the user can add steps by hand or retry
    # from the goal page.
    AppError.record(e, source: self.class.name, user: goal.user, context: { goal_id: goal.id, append: append })
  ensure
    # Stamp even on failure so the "breaking into steps…" state can't stick,
    # and refresh the owner's board either way.
    if goal&.persisted?
      goal.update_column(:broken_down_at, Time.current)
      Turbo::StreamsChannel.broadcast_refresh_to(goal.user, :tasks)
    end
  end
end
