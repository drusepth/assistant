module Travel
  # The forward half of the Travel hub (D-trip-spine): where you'll be,
  # when you move next, and what still isn't booked. Computed fresh per
  # request from the viewer's trips — own and joined — like every other
  # panel service (the CareRadar/MonthSummary idiom).
  #
  # The warnings are the point. A household moving every two months lives
  # or dies by "is the next place actually booked", so anything planned but
  # unbooked inside the booking lead time gets named, as does any run of
  # nights inside a trip with no stay covering them.
  class Outlook
    # How far ahead the "next moves" list looks…
    HORIZON_DAYS = 120
    # …and how close an unbooked stay or leg has to be before it becomes a
    # warning rather than a plan. Two months out is a plan; six weeks out
    # is a booking somebody needs to make.
    BOOKING_LEAD_DAYS = 45
    # Two trips this close together are one continuous run — the nights
    # between them are the drive, and somebody has to sleep somewhere. A
    # longer gap is going home between trips, which is nobody's problem.
    CHAIN_GAP_NIGHTS = 3
    MOVES_SHOWN = 8

    Warning = Data.define(:trip, :message)

    def initialize(viewer, today: Date.current)
      @viewer = viewer
      @today = today
    end

    attr_reader :today

    def trips = @trips ||= Trip.involving(@viewer).includes(:stays, :legs).to_a

    def current_trip = @current_trip ||= trips.find { |trip| trip.underway?(today) }

    # The stay you're inside right now — the "you are here" line.
    def current_stay
      return @current_stay if defined?(@current_stay)

      @current_stay = active_trips.flat_map { |trip| trip.stays.to_a }
        .select { |stay| stay.covers?(today) }.min_by(&:check_in)
    end

    # Upcoming stays and legs across every trip, one chronological run —
    # the next few moves of the nomad's year, whatever trip they belong to.
    def next_moves
      @next_moves ||= active_trips.flat_map { |trip|
        trip.stays.select { |stay| stay.check_out >= today && stay != current_stay } +
          trip.legs.select { |leg| (leg.ends_on || leg.starts_on) >= today }
      }.sort_by { |item|
        date = item.is_a?(Stay) ? item.check_in : item.starts_on
        [ date, item.is_a?(Stay) ? 1 : 0, item.id ]
      }.select { |item| start_of(item) <= today + HORIZON_DAYS }.first(MOVES_SHOWN)
    end

    def warnings
      @warnings ||= conflict_warnings + unbooked_warnings + gap_warnings +
        between_trip_warnings + lodging_missing_warnings
    end

    def any? = current_stay.present? || next_moves.any? || warnings.any?

    private
      def active_trips = @active_trips ||= trips.reject { |trip| trip.past?(today) }

      def start_of(item) = item.is_a?(Stay) ? item.check_in : item.starts_on

      def within_lead?(date) = date <= today + BOOKING_LEAD_DAYS

      def unbooked_warnings
        active_trips.flat_map do |trip|
          items = trip.unbooked_stays.select { |stay| stay.check_out >= today && within_lead?(stay.check_in) } +
            trip.unbooked_legs.select { |leg| leg.starts_on >= today && within_lead?(leg.starts_on) }
          items.map do |item|
            Warning.new(trip:, message: "#{item.display_name} (#{item.period}) isn't booked yet")
          end
        end
      end

      def gap_warnings
        active_trips.select { |trip| trip.stays.any? }.flat_map do |trip|
          trip.lodging_gaps
            .select { |gap| gap.last >= today && within_lead?(gap.first) }
            .map do |gap|
              nights = (gap.last - gap.first).to_i + 1
              Warning.new(trip:, message: "#{trip.name}: nowhere to sleep #{night_span(gap.first, gap.last)} (#{nights == 1 ? "1 night" : "#{nights} nights"})")
            end
        end
      end

      def lodging_missing_warnings
        active_trips.select { |trip| trip.stays.none? && trip.timeline.any? && within_lead?(trip.starts_on) }
          .map { |trip| Warning.new(trip:, message: "#{trip.name} has no lodging yet") }
      end

      # Two stays claiming the same night is a double booking — somebody is
      # paying twice or somebody misread a date, and either way it needs
      # eyes now, not at check-in. Every still-fixable overlap warns,
      # whatever trips the two stays belong to.
      def conflict_warnings
        stays = active_trips.flat_map { |trip| trip.stays.to_a }.sort_by { |stay| [ stay.check_in, stay.id ] }
        stays.combination(2).filter_map do |first, second|
          overlap_start = [ first.check_in, second.check_in ].max
          overlap_end = [ first.check_out, second.check_out ].min
          next if overlap_start >= overlap_end || overlap_end <= today

          Warning.new(trip: first.trip,
            message: "Double-booked: #{first.display_name} and #{second.display_name} overlap #{night_span(overlap_start, overlap_end - 1)}")
        end
      end

      # The nights between two trips that chain (docs/TRIPS_PLAN.md §4):
      # trip A ends, trip B starts a night or three later, and those nights
      # belong to neither trip's own gap check. Only trips being actively
      # planned chain — both need at least one stay — and any trip's stay
      # can cover the road night, so the drive never has to be its own trip.
      def between_trip_warnings
        all_stays = trips.flat_map { |trip| trip.stays.to_a }
        trips.sort_by(&:starts_on).each_cons(2).filter_map do |first, second|
          nights_between = (second.starts_on - first.ends_on).to_i
          next unless nights_between.between?(1, CHAIN_GAP_NIGHTS)
          next if first.stays.none? || second.stays.none?

          nights = (first.ends_on...second.starts_on).reject { |night| all_stays.any? { |stay| stay.covers?(night) } }
          next if nights.empty? || nights.last < today || !within_lead?(nights.first)

          Warning.new(trip: second,
            message: "Nowhere to sleep between #{first.name} and #{second.name} (#{night_span(nights.first, nights.last)}, #{nights.size == 1 ? "1 night" : "#{nights.size} nights"})")
        end
      end

      def night_span(first, last)
        return first.strftime("%b %-d") if first == last

        "#{first.strftime("%b %-d")} – #{last.strftime("%b %-d")}"
      end
  end
end
