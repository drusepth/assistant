class BreakDownGoalJob < ApplicationJob
  include RetriesModelCalls

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
    if will_retry?(e)
      @retrying = true
      raise
    end

    # Best-effort (D16): out of chances, the goal is left as a single unplanned
    # item — the user can add steps by hand or retry from the goal page.
    record_failure(e, user: goal.user, context: { goal_id: goal.id, append: append })
  ensure
    # Stamp even on failure so the "breaking into steps…" state can't stick,
    # and refresh the owner's board either way — but not between retries, or
    # the goal would drop out of that state and back into it on every attempt.
    settle(goal) unless @retrying
  end

  private
    def settle(goal)
      return unless goal&.persisted?

      goal.update_column(:broken_down_at, Time.current)
      Turbo::StreamsChannel.broadcast_refresh_to(goal.user, :tasks)
    end
end
