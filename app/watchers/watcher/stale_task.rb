module Watcher
  # The Dashboard and Today page only speak about tasks with due dates, so an
  # undated task parked in the board's Later column can quietly vanish from
  # every daily surface. Once it has sat there a few weeks it earns a nudge
  # whose accept pulls the existing task into Today — nothing new is created.
  # Sectionless (tasks live everywhere; each suggestion files under its
  # task's own sections), and goal-linked tasks are goal-stall's beat.
  class StaleTask < Base
    self.section_slugs = []

    STALE_AFTER = 3.weeks
    # At most this many live stale-task nudges at a time — the point is to
    # rescue forgotten tasks, not to rebuild the backlog as a wall of nudges.
    # Dealing with one frees its slot, and the next scan brings the next
    # oldest.
    LIMIT = 3

    def scan
      slots = LIMIT - user.suggestions.actionable.where(watcher_slug: self.class.slug).count
      return unless slots.positive?

      stale_tasks.each do |task|
        break unless slots.positive?

        slots -= 1 if propose(
          # A monthly bucket, the goal-stall convention: a dismissal quiets
          # this task for the rest of the month, then it may fairly return.
          fingerprint: "task:#{task.id}/#{Date.current.strftime("%Y-%m")}",
          title: "“#{task.title}” has been waiting since #{task.created_at.strftime("%B %-d")}",
          body: "It has no date and sits in Later, so nothing ever brings it up. " \
            "Give it today — or dismiss it guilt-free.",
          action: { "schedule_task" => { "id" => task.id } },
          sections: task.sections.map(&:slug)
        )
      end
    end

    private
      def stale_tasks
        user.tasks.open.where(due_on: nil, bucket: :later, goal_id: nil)
            .where(created_at: ..STALE_AFTER.ago)
            .includes(:sections).order(:created_at)
      end
  end
end
