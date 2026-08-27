module Travel
  # The itinerary drawn on the self-drawn basemap (D-stay-pins): one pin
  # per located stay, a line for the route between them, in check-in order.
  #
  # It rides Photos::Map for everything hard — the padded window, min-span,
  # aspect shaping, the two basemaps and the gazetteer lettering all came
  # from the `bounds:` seam, so this class only supplies the points. The
  # inner map is built over an empty photo scope: no photo is read, which
  # is what makes this drawable for every traveller on a shared trip —
  # stay coordinates come from typed location text matched against the
  # local gazetteer, never from anyone's EXIF (the Q14 line).
  class ItineraryMap
    Waypoint = Data.define(:stay, :x, :y) do
      def label = stay.location
    end

    def initialize(stays)
      @stays = stays.select(&:located?)
    end

    def any? = waypoints.any?

    def waypoints
      @waypoints ||= @stays.map do |stay|
        Waypoint.new(stay: stay,
          x: (stay.longitude.to_f + 180.0) / 360.0 * Photos::Map::WIDTH,
          y: (90.0 - stay.latitude.to_f) / 180.0 * Photos::Map::HEIGHT)
      end
    end

    # The route, as consecutive pairs — skipping a leg that goes nowhere
    # (two stays in the same town draw one pin, not a zero-length line).
    def segments
      waypoints.each_cons(2).reject { |a, b| a.x == b.x && a.y == b.y }
    end

    def map
      @map ||= Photos::Map.new(Photo.none, bounds: bounds)
    end

    delegate :view_box, :aspect_ratio, :zoomed?, :window_box, :context_labels, :position, to: :map

    private
      # The corners of everywhere the itinerary goes. Min/max is honest
      # everywhere except an itinerary crossing the antimeridian, which
      # would draw the long way around — accepted until somebody island-
      # hops the Pacific with this.
      def bounds
        latitudes = @stays.map { |stay| stay.latitude.to_f }
        longitudes = @stays.map { |stay| stay.longitude.to_f }
        { south: latitudes.min, north: latitudes.max,
          west: longitudes.min, east: longitudes.max }
      end
  end
end
