module Health
  # The care radar (docs/HEALTH.md): per kind of routine care, is something
  # booked, are you on track, are you due, or does the app simply not know?
  # It is a derived view — deterministic keyword classification over one
  # user's Health-tagged events, zero schema of its own — so it can never
  # disagree with the calendar it reads. Classification is deliberately
  # conservative: an event the radar can't confidently place ("Therapy",
  # "Cardiology follow-up") just doesn't count, rather than counting as the
  # wrong thing — and `events.care_kind` is the user's override for the
  # misses (count this as a checkup / don't count this at all).
  #
  # Whose care, and who's looking: `user` is whose care this is; `viewer`
  # (default: the same user) is the visibility wall. A parent viewing a
  # kid's radar reads exactly the events the kid shares with them —
  # `visible_to` is the only read path (D9), household-care strip included.
  #
  # Tuning (care_settings): a kind can be muted or given a different
  # interval, and custom kinds ("Dermatology", every 12 months) classify by
  # their own label. Settings belong to the user whose care it is.
  class CareRadar
    Kind = Data.define(:key, :label, :provider, :appointment_title, :book_title, :interval_months, :patterns)

    # Registry defaults, in display order. `provider` seeds the find-care
    # tool's specialty input; `appointment_title` seeds the event
    # quick-capture; `book_title` is the watcher's suggestion title.
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

    # An event may be explicitly excluded from the radar ("Refill lisinopril"
    # is health-tagged but not a visit).
    EXCLUDED = "none".freeze

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

    def initialize(user, viewer: user)
      @user = user
      @viewer = viewer
    end

    attr_reader :user, :viewer

    # One Status per effective kind, display order: tuned registry kinds
    # first, then custom kinds. [] when the Health section isn't seeded.
    def statuses
      return [] if health_section_ids.empty?

      @statuses ||= kinds.map do |kind|
        past, future = (events_by_kind[kind.key] || []).partition { |event| event.starts_at < Time.current }
        Status.new(kind: kind, last_visit: past.max_by(&:starts_at), next_visit: future.min_by(&:starts_at))
      end
    end

    # The user's effective kinds: registry defaults minus muted, intervals
    # overridden, plus their custom kinds.
    def kinds
      @kinds ||= begin
        settings = user.care_settings.index_by(&:kind_key)
        tuned = KINDS.filter_map do |kind|
          setting = settings[kind.key]
          next if setting && !setting.enabled?

          setting&.interval_months ? kind.with(interval_months: setting.interval_months) : kind
        end
        tuned + custom_kinds(settings.values.select(&:custom?))
      end
    end

    # "Dental checkup" is dental, not checkup: the generic checkup patterns
    # match last so the specific (and custom) kinds win.
    def classify(title)
      normalized = title.to_s.downcase
      matching_order.find { |kind| kind.patterns.any? { |pattern| normalized.match?(pattern) } }
    end

    private
      def matching_order
        @matching_order ||= kinds.sort_by { |kind| kind.key == "checkup" ? 1 : 0 }
      end

      # The user's manual word beats the keywords: care_kind names a kind
      # (or EXCLUDED), anything else falls back to classification.
      def kind_for(event)
        return nil if event.care_kind == EXCLUDED

        kinds.find { |kind| kind.key == event.care_kind } || classify(event.title)
      end

      def events_by_kind
        @events_by_kind ||= Event.visible_to(viewer).where(user: user)
          .in_section(health_section_ids)
          .where(starts_at: LOOKBACK.ago..)
          .group_by { |event| kind_for(event)&.key }
          .except(nil)
      end

      # A custom kind classifies by its own label, whole phrase only —
      # per-word matching would collide with the registry ("Skin check"
      # would swallow "checkup").
      def custom_kinds(settings)
        settings.select(&:enabled?).sort_by(&:created_at).map do |setting|
          label = setting.label
          Kind.new(
            key: setting.kind_key, label: label, provider: label.downcase,
            appointment_title: label, book_title: "Book a #{label.downcase} visit",
            interval_months: setting.interval_months || 12,
            patterns: [ /#{Regexp.escape(label.downcase)}/ ]
          )
        end
      end

      def health_section_ids
        @health_section_ids ||= begin
          health = Section.find_by(slug: "health")
          health ? [ health.id, *health.children.ids ] : []
        end
      end
  end
end
