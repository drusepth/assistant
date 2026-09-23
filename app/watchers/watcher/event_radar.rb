module Watcher
  # Events near your places that are for you, inside the lead time
  # (D-event-radar §7). Pure SQL: the judgment was made by Radar::Match in
  # its own job, and a row the user saved themselves carries its own. This
  # only decides *when* to speak — inside the owning place's lead window,
  # soonest first, at most a handful per place per scan, one per series —
  # and what accepting does: the row lands on the calendar (or, for a
  # volunteer opening, on the board) through the same path the river's
  # verb takes, so the event is identical whichever way it arrived.
  #
  # Hobbies and People both govern it — the loudest dial wins — so a
  # household that turned People up for its circle hears about openings
  # daily and about concerts weekly.
  class EventRadar < Base
    self.section_slugs = %w[ hobbies people ]

    MAX_PER_PLACE = 5

    def scan
      # Trip windows first (D-place-subscriptions): a stay's nights are the
      # lead time for the place it lands in, and a row proposed here wears
      # Travel — so the trip page's "While you're there" and the hub's card
      # show the same nudge.
      Radar::Windows.new(user).all.each do |window|
        next unless window.place.alerts?

        candidates(window.place, range: window.range).first(MAX_PER_PLACE).each { |row| propose_for(row, travel: true) }
      end
      user.places.alerting.each do |place|
        candidates(place).first(MAX_PER_PLACE).each { |row| propose_for(row) }
      end
    end

    # The world moved on: the row was rejected, hidden, withdrawn, pruned,
    # or the user put it on their calendar or board themselves — and a
    # nudge about a thing already on your calendar is the D-reminders
    # failure restated. (The date itself is `expires_on`.)
    def resolved?(suggestion)
      return false unless (id = subject_id(suggestion, "happening"))

      row = Happening.for_user(user).find_by(id: id)
      return true if row.nil?

      row.hidden? || row.withdrawn? || row.linked? || !row.matched?
    end

    # Dismissing the nudge is "not this" said on the suggestion instead of
    # the row (D-event-radar §5.4): the match is tombstoned so the title
    # comes back as an example, and both ways of saying no teach the same
    # lesson. A saved row was the user's own judgment, so it is only hidden.
    def dismissed(suggestion)
      return unless (id = subject_id(suggestion, "happening"))

      row = Happening.for_user(user).find_by(id: id)
      return if row.nil?

      row.provenance_saved? ? row.hide! : row.matches.each(&:reject!)
    end

    private
      def candidates(place, range: place.lead_window)
        rows = Happening.where(listing_source_id: place.listing_sources.select(:id))
          .live.visible.in_range.unlinked.matched.upcoming
          .includes(:matches, listing_source: :place).by_start.to_a
        rows = rows.select { |row| row.kind_opening? || range.cover?(row.starts_at.to_date) }
        rows = rows.reject { |row| user.suggestions.exists?(fingerprint: "#{self.class.slug}/happening:#{row.id}") }
        seen = Set.new
        rows.select { |row| seen.add?(row.series_uid.presence || row.uid) }
      end

      def propose_for(row, travel: false)
        match = row.match
        propose(
          fingerprint: "happening:#{row.id}",
          title: title_for(row, match),
          body: body_for(row, match),
          action: {
            "happening" => row.id,
            "accept_label" => row.kind_opening? ? "Make a task" : "Add to calendar",
            "expires_on" => expiry_for(row)&.iso8601
          }.compact,
          sections: sections_for(row, match) + (travel ? [ "travel" ] : [])
        )
      end

      # Date-first, because a date is a commitment and a name is a pile; an
      # opening is organization-first, having no date.
      def title_for(row, match)
        if row.kind_opening?
          "#{row.title} — volunteers wanted#{" (#{match.label})" if match}"
        else
          tail = [ match&.label, distance_for(row) ].compact.join(", ")
          "#{row.starts_at.strftime("%a %-d %b")} · #{row.title}#{" (#{tail})" if tail.present?}"
        end
      end

      def body_for(row, match)
        parts = []
        parts << (row.provenance_saved? ? "You saved this yourself." : match&.because&.then { |why| why.sub(/\A[a-z]/, &:upcase).delete_suffix(".") + "." })
        parts << row.location if row.location.present?
        parts << when_for(row)
        parts << "From #{row.source_name}."
        parts.compact.join(" ")
      end

      def when_for(row)
        return "Open now." if row.kind_opening?
        return row.starts_at.strftime("%A %-d %B, all day.") if row.all_day?

        row.starts_at.strftime("%A %-d %B at %-l:%M %P.").sub(":00", "")
      end

      def distance_for(row)
        return nil if row.distance_km.blank?

        user.units.distance_phrase(row.distance_km)
      end

      def expiry_for(row)
        row.kind_opening? ? row.expires_on : row.starts_at.to_date
      end

      # What the suggestion — and the event or task it lands — is filed
      # under: the radar's section, plus the lens it matched, plus People
      # for a cause.
      def sections_for(row, match)
        slugs = row.kind_opening? ? %w[ people ] : %w[ hobbies ]
        slugs << "people" if match&.causes?
        slugs << "education" if match&.subject?
        slugs << match.section.slug if match&.section
        slugs.uniq
      end
  end
end
