module Watcher
  # The first watcher (M3.1), grown per-kind (docs/HEALTH.md): the care
  # radar knows, per kind of routine care, when the last visit was and
  # whether anything is booked — so the nudge can be "book a dental
  # cleaning, your last was 8 months ago" instead of a generic prod.
  # Signal discipline, stay-in-touch style: a per-kind nudge needs
  # per-kind history (no logged dental visit → no dental nudge; the radar
  # panel is the pull surface for unknowns). The original generic nudge
  # survives for the zero-signal case — no Health event in a year and none
  # upcoming. Scans only the user's own events — a spouse's shared
  # appointment is not your checkup.
  class CheckupCadence < Base
    self.section_slugs = %w[ health ]

    LOOKBACK = 12.months

    def scan
      statuses = Health::CareRadar.new(user).statuses
      return if statuses.empty?

      statuses.select { |status| status.state == :due }.each { |status| propose_kind(status) }
      propose_generic if statuses.all? { |status| status.state == :unknown } && calendar_silent?
      proposals
    end

    # The visit got booked or logged. Both halves ask the same question the
    # scan asked: a per-kind nudge retires once the radar stops calling that
    # kind due (something is on the calendar, or a visit got logged), and
    # the zero-signal generic one retires once anything health-shaped is on
    # the calendar at all.
    def resolved?(suggestion)
      # "checkup_cadence/dental/2026h2" — per kind; "checkup_cadence/2026h2"
      # — the generic one, which carries no kind segment.
      _, kind_key, period = suggestion.fingerprint.split("/")
      return !calendar_silent? if period.nil?

      status = Health::CareRadar.new(user).statuses.find { |candidate| candidate.kind.key == kind_key }
      status.nil? || status.state != :due
    end

    private
      # Accepting opens the find-care tool prefilled with the right kind of
      # provider — the reconnect/stay-in-touch convention. A non-clinical
      # kind (haircut) has no business in a find-a-doctor tool: it accepts
      # into a plain task instead.
      def propose_kind(status)
        propose(
          fingerprint: "#{status.kind.key}/#{period}",
          title: status.kind.book_title,
          body: "Your last #{status.kind.history_phrase} was #{status.last_visit_on.strftime("%B %Y")} — " \
                "about every #{status.kind.cadence_phrase} is the usual rhythm, and nothing's booked yet.",
          action: book_action(status.kind)
        )
      end

      def book_action(kind)
        if kind.clinical?
          { "tool" => { "slug" => "find_care", "inputs" => { "specialty" => kind.provider } } }
        else
          { "task" => { "title" => kind.book_title } }
        end
      end

      def propose_generic
        propose(
          fingerprint: period,
          title: "Book a health checkup",
          body: "Nothing health-related on your calendar in the last year, and nothing coming up. " \
                "A routine visit is how small things stay small.",
          action: { "task" => { "title" => "Book a checkup appointment" } }
        )
      end

      def calendar_silent?
        health = Section.find_by(slug: "health")
        ids = [ health.id, *health.children.ids ]
        Event.where(user: user).in_section(ids).where(starts_at: LOOKBACK.ago..).none?
      end

      # Fingerprints include a half-year bucket: a dismissal quiets a nudge
      # for the rest of the half, then it may fairly return.
      def period = "#{Date.current.year}h#{Date.current.month <= 6 ? 1 : 2}"
  end
end
