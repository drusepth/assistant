module Health
  # The care radar (docs/HEALTH.md): per kind of routine care, is something
  # booked, are you on track, are you due, or does the app simply not know?
  # It is a derived view — deterministic keyword classification over the
  # user's own Health-tagged events, zero schema of its own — so it can
  # never disagree with the calendar it reads. Classification is
  # deliberately conservative: an event the radar can't confidently place
  # ("Therapy", "Cardiology follow-up") just doesn't count, rather than
  # counting as the wrong thing.
  #
  # Own events only: a spouse's shared appointment is not your checkup
  # (the checkup-cadence watcher's rule, inherited).
  class CareRadar
    Kind = Data.define(:key, :label, :provider, :appointment_title, :book_title, :interval_months, :patterns)

    # Display order. `provider` seeds the find-care tool's specialty input;
    # `appointment_title` seeds the event quick-capture; `book_title` is the
    # watcher's suggestion title.
    KINDS = [
      Kind.new(
        key: "checkup", label: "Doctor checkup", provider: "primary care doctor",
        appointment_title: "Annual physical", book_title: "Book a checkup",
        interval_months: 12,
        patterns: [ /check[ -]?up/, /physical(?!\s*therap)/, /annual (exam|visit)/, /wellness/, /primary care/, /\bpcp\b/, /physician/ ]
      ),
      Kind.new(
        key: "dental", label: "Dental", provider: "dentist",
        appointment_title: "Dental cleaning", book_title: "Book a dental cleaning",
        interval_months: 6,
        patterns: [ /dent/, /\bteeth\b/, /\btooth\b/, /hygienist/, /orthodont/ ]
      ),
      Kind.new(
        key: "vision", label: "Vision", provider: "eye doctor",
        appointment_title: "Eye exam", book_title: "Book an eye exam",
        interval_months: 24,
        patterns: [ /\beyes?\b/, /vision/, /optometr/, /ophthalmolog/, /optician/, /glasses/, /contact lens/ ]
      )
    ].freeze

    # "Dental checkup" is dental, not checkup: the generic checkup patterns
    # match last so the specific kinds win.
    MATCHING_ORDER = KINDS.sort_by { |kind| kind.key == "checkup" ? 1 : 0 }.freeze

    # Far enough back to catch a vision visit one missed cycle ago.
    LOOKBACK = 3.years

    Status = Data.define(:kind, :last_visit, :next_visit) do
      def state
        return :booked if next_visit
        return :unknown unless last_visit

        due_on <= Date.current ? :due : :ok
      end

      def last_visit_on = last_visit&.starts_at&.to_date
      def next_visit_on = next_visit&.starts_at&.to_date
      def due_on = last_visit_on && (last_visit_on >> kind.interval_months)
    end

    def self.classify(title)
      normalized = title.to_s.downcase
      MATCHING_ORDER.find { |kind| kind.patterns.any? { |pattern| normalized.match?(pattern) } }
    end

    def initialize(user)
      @user = user
    end

    # One Status per kind, in display order; [] when the Health section
    # isn't seeded (nothing to tag against, nothing to say).
    def statuses
      return [] if health_section_ids.empty?

      @statuses ||= KINDS.map do |kind|
        past, future = (events_by_kind[kind] || []).partition { |event| event.starts_at < Time.current }
        Status.new(kind: kind, last_visit: past.max_by(&:starts_at), next_visit: future.min_by(&:starts_at))
      end
    end

    private
      attr_reader :user

      def events_by_kind
        @events_by_kind ||= user.events.in_section(health_section_ids)
          .where(starts_at: LOOKBACK.ago..)
          .group_by { |event| self.class.classify(event.title) }
          .except(nil)
      end

      def health_section_ids
        @health_section_ids ||= begin
          health = Section.find_by(slug: "health")
          health ? [ health.id, *health.children.ids ] : []
        end
      end
  end
end
