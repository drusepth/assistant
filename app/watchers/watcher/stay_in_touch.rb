module Watcher
  # "It's been a while since you talked to Mom." The signal is the
  # deliberately manual last_contacted_on (Q8: one tap on the person page —
  # the app can't see your texts and shouldn't pretend to), so this watcher
  # only ever speaks about people the user has logged contact with — and,
  # since D-people-dashboard, only about the circle: relationships the user chose to tend.
  # Accepting opens the Reconnect tool prefilled.
  class StayInTouch < Base
    self.section_slugs = %w[ people ]

    QUIET_AFTER = 90.days

    def scan
      user.people.circle.where(last_contacted_on: ..QUIET_AFTER.ago.to_date).find_each do |person|
        days = (Date.current - person.last_contacted_on).to_i
        propose(
          fingerprint: "person:#{person.id}/#{quarter}",
          title: "Reach out to #{person.name}",
          body: "It's been about #{days / 30} months since you last logged contact.",
          action: { "tool" => { "slug" => "reconnect", "inputs" => { "person_id" => person.id.to_s } } },
          sections: (self.class.section_slugs + person.sections.map(&:slug)).uniq
        )
      end
    end

    # They talked. The signal that raised this nudge is the same one that
    # retires it: a logged contact inside the quiet window — from the one-tap
    # button on the person's page, or from accepting this very suggestion —
    # means the app has no business still asking.
    def resolved?(suggestion)
      return false unless (id = subject_id(suggestion, "person"))

      person = user.people.find_by(id: id)
      return true if person.nil? || person.last_contacted_on.nil?

      person.last_contacted_on > QUIET_AFTER.ago.to_date
    end

    private
      # One nudge per person per quarter, even across dismissals.
      def quarter = "#{Date.current.year}q#{(Date.current.month - 1) / 3 + 1}"
  end
end
