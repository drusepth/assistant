module Watcher
  # Applications die of silence (docs/CAREER.md §4): an open application
  # task that hasn't moved in ten days earns a follow-up nudge whose accept
  # creates the follow-up task. Stale-task's shape with a shorter fuse and a
  # Career filter; capped so a big search never becomes a wall of nudges.
  class ApplicationFollowUp < Base
    self.section_slugs = %w[ career ]

    QUIET_AFTER = 10.days
    LIMIT = 3

    def scan
      slots = LIMIT - user.suggestions.actionable.where(watcher_slug: self.class.slug).count
      return unless slots.positive?

      waiting_applications.each do |task|
        break unless slots.positive?

        slots -= 1 if propose(
          # Monthly buckets (the goal-stall convention): a dismissal quiets
          # this application for the rest of the month.
          fingerprint: "task:#{task.id}/#{Date.current.strftime("%Y-%m")}",
          title: "“#{task.title}” has sat quiet for #{(Date.current - task.updated_at.to_date).to_i} days",
          body: "A short, polite follow-up moves applications out of the pile more often than people expect.",
          action: { "task" => { "title" => "Follow up on: #{task.title}" } }
        )
      end
    end

    private
      def waiting_applications
        career = Section.find_by(slug: "career")
        return Task.none unless career

        user.tasks.open.in_section(career.id)
          .where("title LIKE '%appl%' OR title LIKE '%Appl%'")
          .where(updated_at: ..QUIET_AFTER.ago)
          .order(:updated_at)
      end
  end
end
