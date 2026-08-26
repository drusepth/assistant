module Sections
  module Panels
    # The Travel hub's lead panel (D-travel-facet, D-trip-spine;
    # docs/TRAVEL.md, docs/TRIPS_PLAN.md).
    #
    # Three things, in the order a travelling household needs them: where
    # you'll be next and what still isn't booked (the outlook), the trips
    # themselves — planned ahead or found in the photos — and the map of
    # everywhere your camera has been.
    #
    # Neither the map nor the detector is filtered to Travel-tagged items.
    # Sections are lenses over one pool, and the honest lens for "where
    # have I been" is every photo that knows where it was taken, not the
    # subset somebody remembered to tag.
    class Travel < Panel
      # More than this and the hub is a list rather than a hub; the rest
      # are a click away.
      PAST_TRIPS_SHOWN = 6
      SUGGESTIONS_SHOWN = 4

      def map = @map ||= Photos::Map.new(viewer.photos)

      def outlook = @outlook ||= ::Travel::Outlook.new(viewer)

      # Own trips plus household trips the viewer was added to
      # (D-trip-companions) — the hub answers for the household's plans,
      # not just the viewer's rows.
      def trips = outlook.trips

      def upcoming_trips
        @upcoming_trips ||= trips.reject(&:past?).sort_by(&:starts_on)
      end

      def past_trips
        @past_trips ||= trips.select(&:past?).sort_by(&:starts_on).reverse
      end

      # Trips found in the photos that the user hasn't kept yet. A candidate
      # overlapping a saved trip is that trip, seen again — not a second
      # one — so it drops out of the offer rather than nagging.
      def suggestions
        @suggestions ||= detector.candidates
          .reject { |candidate| trips.any? { |trip| trip.overlaps?(candidate.starts_on, candidate.ends_on) } }
          .sort_by { |candidate| -candidate.starts_on.to_time.to_i }
          .first(SUGGESTIONS_SHOWN)
      end

      def shown_past_trips = past_trips.first(PAST_TRIPS_SHOWN)
      def more_past_trips = [ past_trips.size - PAST_TRIPS_SHOWN, 0 ].max

      def unplaced_count = @unplaced_count ||= viewer.photos.where(latitude: nil).count

      def photos_count = @photos_count ||= viewer.photos.count

      private
        def detector = @detector ||= ::Travel::Trips.new(map)
    end
  end
end
