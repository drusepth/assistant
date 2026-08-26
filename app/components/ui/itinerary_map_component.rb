module Ui
  # The itinerary on the basemap (D-stay-pins): numbered pins in check-in
  # order joined by a route line. Subclasses the photo map component for
  # the land machinery — same files, same window logic, different dots.
  #
  # A pin's number is its place in the run, its color is the booking bit
  # (the same register as the chips), and clicking it opens the stay.
  class ItineraryMapComponent < PhotoMapComponent
    # map: a Travel::ItineraryMap.
    def initialize(map:)
      super
    end

    def pin_classes(waypoint)
      waypoint.stay.booked? ? "bg-primary-600" : "bg-amber-500"
    end

    def summary
      "Map of the itinerary: " +
        map.waypoints.map.with_index(1) { |waypoint, index| "#{index}. #{waypoint.label}" }.join(", ") +
        ". Each pin opens that stay."
    end
  end
end
