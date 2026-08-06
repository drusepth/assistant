module Watcher
  # The flagship Hobbies watcher (docs/HOBBIES.md §4): a hobby lens with no
  # activity in the window — nothing added, nothing scheduled, nothing
  # checked off, nothing upcoming — earns one gentle nudge whose accept
  # action puts a session on the calendar, on a day that looks free. Pure
  # SQL over the user's own data; a lens younger than the window is left
  # alone (adding a hobby is not neglecting it).
  class NeglectedHobby < Base
    self.section_slugs = %w[ hobbies ]

    WINDOW = 6.weeks

    def scan
      hobby_lenses.each do |lens|
        next if lens.created_at > cutoff
        next if touched_since_cutoff?(lens) || upcoming_event?(lens)

        session_on = free_day
        propose(
          # A monthly bucket, like goal-stall: a dismissal quiets this lens
          # for the rest of the month, then it may fairly return.
          fingerprint: "lens:#{lens.id}/#{Date.current.strftime("%Y-%m")}",
          title: "It's been a while since anything #{lens.name}",
          body: "Nothing #{lens.name} has been added, scheduled, or checked off since " \
            "#{cutoff.to_date.strftime("%B %-d")}. #{session_on.strftime("%A")} looks free if you want a session.",
          action: { "event" => { "title" => "#{lens.name} session", "starts_at" => session_on.iso8601, "all_day" => true } },
          sections: [ "hobbies", lens.slug ]
        )
      end
    end

    private
      def hobbies = @hobbies ||= Section.find_by(slug: "hobbies")

      def hobby_lenses
        hobbies ? hobbies.children.where(custom: true) : Section.none
      end

      def cutoff = @cutoff ||= WINDOW.ago

      def touched_since_cutoff?(lens)
        [ user.events, user.tasks, user.notes, user.documents, user.goals ].any? do |scope|
          scope.in_section(lens.id).where(created_at: cutoff..).exists?
        end || user.tasks.in_section(lens.id).where(completed_at: cutoff..).exists?
      end

      def upcoming_event?(lens)
        user.events.in_section(lens.id).where(starts_at: Time.current..).exists?
      end

      # The first of the next seven days with nothing on the user's
      # calendar; tomorrow if every day is spoken for.
      def free_day
        @free_day ||= begin
          taken = user.events.where(starts_at: Date.tomorrow.in_time_zone..7.days.from_now.end_of_day)
            .pluck(:starts_at).map(&:to_date)
          (Date.tomorrow..Date.tomorrow + 6).find { |day| taken.exclude?(day) } || Date.tomorrow
        end
      end
  end
end
