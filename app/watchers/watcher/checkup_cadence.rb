module Watcher
  # The first watcher (M3.1): if a user has no Health-tagged event in the
  # past year and none coming up, suggest booking a checkup. Scans only the
  # user's own events — a spouse's shared appointment is not your checkup.
  class CheckupCadence < Base
    self.section_slugs = %w[ health ]

    LOOKBACK = 12.months

    def scan
      return if health_section_ids.empty?
      return if Event.where(user: user).in_section(health_section_ids)
                     .where(starts_at: LOOKBACK.ago..).exists?

      propose(
        fingerprint: period,
        title: "Book a health checkup",
        body: "Nothing health-related on your calendar in the last year, and nothing coming up. " \
              "A routine visit is how small things stay small.",
        action: { "task" => { "title" => "Book a checkup appointment" } }
      )
    end

    private
      def health_section_ids
        @health_section_ids ||= begin
          health = Section.find_by(slug: "health")
          health ? [ health.id, *health.children.ids ] : []
        end
      end

      # Fingerprints include a half-year bucket: a dismissal quiets this
      # nudge for the rest of the half, then it may fairly return.
      def period = "#{Date.current.year}h#{Date.current.month <= 6 ? 1 : 2}"
  end
end
