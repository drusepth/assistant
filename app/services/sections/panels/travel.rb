module Sections
  module Panels
    # The Travel hub's lead panel (D-travel-facet, docs/TRAVEL.md).
    #
    # Two things, in the order they matter: the trips you took, and the map
    # of everywhere your camera has been. Both are read out of photos that
    # were already in the library — the section earns its place on day one
    # without asking the user to type anything.
    #
    # Neither is filtered to Travel-tagged items. Sections are lenses over
    # one pool, and the honest lens for "where have I been" is every photo
    # that knows where it was taken, not the subset somebody remembered to
    # tag.
    class Travel < Panel
      # More than this and the hub is a list rather than a hub; the rest are
      # a click away.
      TRIPS_SHOWN = 6
      SUGGESTIONS_SHOWN = 4

      def map = @map ||= Photos::Map.new(viewer.photos)

      def trips = @trips ||= viewer.trips.recent.to_a

      # Trips found in the photos that the user hasn't kept yet. A candidate
      # overlapping a saved trip is that trip, seen again — not a second
      # one — so it drops out of the offer rather than nagging.
      def suggestions
        @suggestions ||= detector.candidates
          .reject { |candidate| trips.any? { |trip| trip.overlaps?(candidate.starts_on, candidate.ends_on) } }
          .sort_by { |candidate| -candidate.starts_on.to_time.to_i }
          .first(SUGGESTIONS_SHOWN)
      end

      def shown_trips = trips.first(TRIPS_SHOWN)
      def more_trips = [ trips.size - TRIPS_SHOWN, 0 ].max

      def unplaced_count = @unplaced_count ||= viewer.photos.where(latitude: nil).count

      def photos_count = @photos_count ||= viewer.photos.count

      private
        def detector = @detector ||= ::Travel::Trips.new(map)
    end
  end
end
