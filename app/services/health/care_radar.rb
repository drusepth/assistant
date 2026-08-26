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
    Kind = Data.define(:key, :label, :provider, :appointment_title, :book_title, :interval, :patterns, :clinical, :generic) do
      # Kinds are clinical unless they say otherwise — a non-clinical kind
      # (the haircut, a groom) is tracked exactly the same way but skips the
      # medical next-clicks (find-care, visit prep) and names itself in copy.
      # A generic kind ("checkup", a pet's "wellness exam") matches last, so
      # the specific kinds win: "Dental checkup" is dental.
      def initialize(clinical: true, generic: false, **rest) = super

      def clinical? = clinical
      def generic? = generic

      # An interval is a duration, not a number of months (D-pet-care-radar):
      # monthly parasite prevention and a six-week groom don't round to whole
      # months, and `last + interval` needs no branch to handle either.
      def due_after(date) = date + interval

      # Under a quarter, "due since Aug 2026" is too coarse to act on — the
      # month is half over before it says anything.
      def short_cadence? = interval < 3.months

      # The rhythm in words, for copy: "12 months", "6 weeks", "1 month".
      def cadence_phrase = interval.inspect

      # The tuning page thinks in whole months and only ever lists the human
      # kinds, all of which are whole months.
      def interval_months = (interval / 1.month).round

      # Tile copy: "Last visit Feb 2026" / "Last haircut Feb 2026".
      def visit_noun = clinical ? "visit" : label.downcase

      # Watcher copy: "your last dental visit" / "your last haircut".
      def history_phrase = clinical ? "#{label.downcase} visit" : label.downcase
    end

    # Registry defaults, in display order. `provider` seeds the find-care
    # tool's specialty input; `appointment_title` seeds the event
    # quick-capture; `book_title` is the watcher's suggestion title.
    KINDS = [
      Kind.new(
        key: "checkup", label: "Doctor checkup", provider: "primary care doctor",
        appointment_title: "Annual physical", book_title: "Book a checkup",
        interval: 12.months, generic: true,
        patterns: [ /check[ -]?up/, /physical(?!\s*therap)/, /annual (exam|visit)/, /wellness/, /primary care/, /\bpcp\b/, /physician/ ]
      ),
      Kind.new(
        key: "dental", label: "Dental", provider: "dentist",
        appointment_title: "Dental cleaning", book_title: "Book a dental cleaning",
        interval: 6.months,
        patterns: [ /dent/, /\bteeth\b/, /\btooth\b/, /hygienist/, /orthodont/ ]
      ),
      Kind.new(
        key: "vision", label: "Vision", provider: "eye doctor",
        appointment_title: "Eye exam", book_title: "Book an eye exam",
        interval: 24.months,
        patterns: [ /\beyes?\b/, /vision/, /optometr/, /ophthalmolog/, /optician/, /glasses/, /contact lens/ ]
      ),
      # The first non-clinical kind: upkeep, not care. It earns a place on
      # the radar for the same reason the others do — it is a recurring
      # appointment on a rhythm you'd rather not keep in your head — but
      # nothing about it is medical, so it gets none of the medical
      # next-clicks. Grooming sits last, after the care that matters more.
      Kind.new(
        key: "haircut", label: "Haircut", provider: "barber or hair stylist",
        appointment_title: "Haircut", book_title: "Book a haircut",
        interval: 2.months, clinical: false,
        patterns: [ /\bhaircut\b/, /\bhair\b.*\b(cut|trim|appointment)\b/, /barber/, /hairdress/, /hair salon/, /\bstylist\b/ ]
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
      def due_on = last_visit_on && kind.due_after(last_visit_on)
    end

    # `subject` is whose care this is — a User, or a Pet (D-pet-care-radar).
    # `viewer` is the visibility wall: a parent viewing a kid's radar reads
    # exactly the events the kid shares with them, and visible_to is the only
    # read path (D9).
    def initialize(subject, viewer: nil)
      @subject = subject
      @viewer = viewer || (subject.is_a?(Pet) ? subject.user : subject)
    end

    attr_reader :subject, :viewer

    def pet? = subject.is_a?(Pet)

    # The user whose tuning applies. A pet has none yet — she runs on registry
    # defaults until care_settings.subject goes polymorphic.
    def user = pet? ? subject.user : subject

    # One Status per effective kind, display order: tuned registry kinds
    # first, then custom kinds. [] when the Health section isn't seeded.
    def statuses
      return [] if !pet? && health_section_ids.empty?

      @statuses ||= kinds.map do |kind|
        past, future = (events_by_kind[kind.key] || []).partition { |event| event.starts_at < Time.current }
        Status.new(kind: kind, last_visit: past.max_by(&:starts_at), next_visit: future.min_by(&:starts_at))
      end
    end

    # The effective kinds. A pet's come from her species registry and are not
    # yet tunable; a user's are the registry defaults minus muted, intervals
    # overridden, plus their custom kinds.
    def kinds
      return @kinds ||= Pets::CareKinds.for(subject) if pet?

      @kinds ||= begin
        settings = user.care_settings.index_by(&:kind_key)
        tuned = KINDS.filter_map do |kind|
          setting = settings[kind.key]
          next if setting && !setting.enabled?

          setting&.interval_months ? kind.with(interval: setting.interval_months.months) : kind
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
        @matching_order ||= kinds.sort_by { |kind| kind.generic? ? 1 : 0 }
      end

      # The user's manual word beats the keywords: care_kind names a kind
      # (or EXCLUDED), anything else falls back to classification.
      def kind_for(event)
        return nil if event.care_kind == EXCLUDED

        kinds.find { |kind| kind.key == event.care_kind } || classify(event.title)
      end

      def events_by_kind
        @events_by_kind ||= care_events
          .where(starts_at: LOOKBACK.ago..)
          .group_by { |event| kind_for(event)&.key }
          .except(nil)
      end

      # A pet's care is everything tagged with her lens, whoever booked it:
      # the spouse who drove the dog to the vet booked the *dog's* visit, and
      # there is only one dog. (A person's radar is the opposite — a spouse's
      # shared appointment is not your checkup, HEALTH.md §3.)
      #
      # Which is also why a user's radar has to subtract the pet lenses: "Rex —
      # dental cleaning", tagged Health, would otherwise classify as *your*
      # dental and report you on track (D-pet-care-radar).
      def care_events
        return Event.visible_to(viewer).in_section(subject.section_id) if pet?

        scope = Event.visible_to(viewer).where(user: user).in_section(health_section_ids)
        pet_lenses = Pets::Lens.section_ids
        return scope if pet_lenses.empty?

        scope.where.not(id: SectionTagging.where(section_id: pet_lenses, taggable_type: "Event").select(:taggable_id))
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
            interval: (setting.interval_months || 12).months,
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
