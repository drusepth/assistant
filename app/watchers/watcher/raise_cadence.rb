module Watcher
  # The section's flagship nudge (docs/CAREER.md §4), checkup-cadence's
  # twin: when the comp timeline says pay hasn't moved in a year, say so and
  # offer the raise-case tool. Reads only the D30 timeline — granted or
  # logged, never guessed; with no timeline at all, one lifetime invitation
  # to start it (no signal, no nudge — Q8 discipline).
  class RaiseCadence < Base
    self.section_slugs = %w[ career ]

    QUIET_AFTER = 12.months

    def scan
      if (last = Career::CompChange.latest_on(user))
        return if last > QUIET_AFTER.ago.to_date

        months = (Date.current.year * 12 + Date.current.month) - (last.year * 12 + last.month)
        propose(
          # A yearly bucket: a dismissal quiets this for the calendar year,
          # then it may fairly return.
          fingerprint: Date.current.year.to_s,
          title: "It's been #{months} months since your pay last changed",
          body: "Raises go to the people who ask. Your logged wins and tenure are already the case — " \
                "want it written up?",
          action: { "tool" => { "slug" => "raise_case" } }
        )
      elsif career_activity?
        propose(
          # No time bucket: one lifetime invitation, then silence.
          fingerprint: "invite",
          title: "Want me to watch your raise cadence?",
          body: "Log your last pay change on the Career page (or add a pay stub to Documents) " \
                "and I'll flag when it's been too long.",
          action: { "task" => { "title" => "Log your last pay change on the Career page" } }
        )
      end
    end

    private
      def career_activity?
        career = Section.find_by(slug: "career")
        return false unless career

        [ Note, Event, Task, Document, Goal ].any? do |klass|
          klass.where(user: user).in_section(career.id).exists?
        end
      end
  end
end
