module Watcher
  # The first cross-user coordination watcher (D21) — and the proof that
  # coordination needs no new machinery: this is an ordinary watcher whose
  # only difference is querying `visible_to(user)` instead of own-data
  # scopes, so it structurally cannot see (or speak about) anything the
  # other member didn't share. When you and another household member both
  # have timed events on the same day soon, a heads-up suggests
  # coordinating — rides, timing, back-to-back booking.
  class SameDaySync < Base
    self.section_slugs = %w[ people ]

    HORIZON = 14.days

    def scan
      my_busy_days = user.events.where(all_day: false, starts_at: window)
        .pluck(:starts_at).map(&:to_date).to_set
      return if my_busy_days.empty?

      shared_timed_events.group_by { |event| [ event.user, event.starts_at.to_date ] }
        .each do |(owner, date), events|
        next unless my_busy_days.include?(date)

        propose(
          fingerprint: "user:#{owner.id}/#{date.iso8601}",
          kind: :heads_up,
          title: "You and #{owner.name} are both out on #{date.strftime("%A, %B %-d")}",
          body: "#{owner.name} has #{events.map(&:title).to_sentence} that day and so do you — worth coordinating rides or timing?",
          action: { "task" => {
            "title" => "Coordinate #{date.strftime("%b %-d")} with #{owner.name}",
            "due_on" => [ date - 1, Date.current ].max.iso8601
          } }
        )
      end
    end

    private
      def window
        Time.current..HORIZON.from_now.end_of_day
      end

      # visible_to is the entire privacy story (D9/D21): only what the
      # other member explicitly shared can ever appear here.
      def shared_timed_events
        Event.visible_to(user).where.not(user_id: user.id)
          .where(all_day: false, starts_at: window).includes(:user, :sections)
      end
  end
end
