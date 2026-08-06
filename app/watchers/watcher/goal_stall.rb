module Watcher
  # An active goal where nothing has been completed lately and nothing is
  # scheduled soon has quietly died — surface it before it's forgotten.
  # Sectionless: goals live everywhere, so the suggestion is filed under
  # the goal's own sections and the watcher runs at the Quiet default.
  class GoalStall < Base
    self.section_slugs = []

    STALL_AFTER = 14.days
    SCHEDULED_HORIZON = 7.days

    def scan
      user.goals.active.where(created_at: ..STALL_AFTER.ago)
          .includes(:tasks, :sections).find_each do |goal|
        next if goal.tasks.none?
        next if recently_worked?(goal) || scheduled_soon?(goal)

        propose(
          fingerprint: "goal:#{goal.id}/#{Date.current.strftime("%Y-%m")}",
          title: "“#{goal.title}” looks stalled",
          body: "No step finished in two weeks and none scheduled. Momentum beats motivation — one small step restarts it.",
          action: { "task" => { "title" => "Spend 15 minutes on “#{goal.title}”", "due_on" => Date.current.iso8601 } },
          sections: goal.sections.map(&:slug)
        )
      end
    end

    private
      def recently_worked?(goal)
        goal.tasks.any? { |task| task.completed_at && task.completed_at >= STALL_AFTER.ago }
      end

      def scheduled_soon?(goal)
        goal.tasks.any? { |task| !task.completed? && task.due_on && task.due_on <= SCHEDULED_HORIZON.from_now.to_date }
      end
  end
end
