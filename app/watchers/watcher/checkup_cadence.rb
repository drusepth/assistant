module Watcher
  # The first watcher (M3.1): a year of health silence is a signal, and it
  # comes entirely from SQL — no Health-tagged event on the user's calendar
  # in the past QUIET_MONTHS and none upcoming. Accepting lands a concrete
  # placeholder Event on a quiet weekday about two weeks out — a real date
  # the user can drag beats a vague intention. Fingerprinted by year, so a
  # dismissal quiets it until next year, not forever.
  class CheckupCadence < Base
    self.section_slugs = %w[ health ]

    QUIET_MONTHS = 12

    def scan
      return unless health_section
      return if user.events.in_section(health_section.id)
        .where(starts_at: QUIET_MONTHS.months.ago..).exists?

      propose(
        fingerprint: Date.current.year.to_s,
        title: "You might be due for a checkup",
        body: "Nothing health-related has been on your calendar for a year, and nothing is coming up. Routine checkups are how small things stay small.",
        action: {
          "type" => "create_event",
          "event" => { "title" => "Book a checkup", "date" => suggested_date.iso8601 }
        }
      )
    end

    private
      def health_section
        @health_section ||= Section.find_by(slug: "health")
      end

      def suggested_date
        (14..28).each do |offset|
          date = Date.current + offset
          next if date.on_weekend?
          return date unless user.events.where(starts_at: date.in_time_zone.all_day).exists?
        end
        Date.current + 14
      end
  end
end
