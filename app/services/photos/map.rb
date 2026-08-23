module Photos
  # Geotagged photos as pins on a world map (D-travel-facet).
  #
  # Three things this deliberately does not do:
  #
  # * **It never asks anyone where you've been.** The basemap ships in the
  #   repo (`app/assets/images/world_land.svg`, see `script/build_world_map.rb`)
  #   and the projection is arithmetic, so drawing the map of your own life
  #   costs zero requests to anybody. A tile host would see every place its
  #   owner has ever photographed, which is exactly the kind of thing this
  #   app exists not to hand over.
  # * **It never geocodes.** Pins carry coordinates, counts and dates — not
  #   place names, because naming a coordinate means a lookup service (see
  #   above) or a model guessing, and a confidently wrong "Paris" is worse
  #   than an honest dot.
  # * **It only ever plots the viewer's own photos.** Coordinates are
  #   owner-only (Q14), and a shared photo's location is not the grantee's
  #   to see — a map is exactly the surface that would leak it.
  #
  # The projection is plate carrée, matching the generated SVG's viewBox:
  #
  #   x = (lon + 180) / 360 * 1000        y = (90 - lat) / 180 * 500
  class Map
    WIDTH = 1000.0
    HEIGHT = 500.0

    # The default window crops the empty polar bands — nobody's holiday
    # snaps live at 88°N — but only as a default: a photo outside it pushes
    # the window back out (see #view_box) rather than being quietly dropped
    # off the edge of its own map.
    DEFAULT_TOP_LAT = 82.0
    DEFAULT_BOTTOM_LAT = -58.0
    WINDOW_PADDING = 20.0

    # Clustering distance in map units (1 unit = 0.36°). At 6 units two pins
    # can still be told apart at the size the map renders, and cities an
    # hour apart stay separate pins — London and Paris are ~9.6 units, and
    # merging them would be a lie about where you'd been.
    CLUSTER_RADIUS = 6.0
    CELL = CLUSTER_RADIUS * 2
    # The same radius in degrees, for the Photo.near box a pin links to.
    CLUSTER_DEGREES = (CLUSTER_RADIUS / HEIGHT * 180.0).round(4)

    # A cluster of photos taken in roughly one spot.
    class Pin
      attr_reader :ids, :x, :y, :latitude, :longitude, :first_taken_at, :last_taken_at

      def initialize(id, latitude, longitude, taken_at)
        @ids = [ id ]
        @latitude = latitude
        @longitude = longitude
        @first_taken_at = @last_taken_at = taken_at
        recompute
      end

      def add(id, latitude, longitude, taken_at)
        @latitude = ((@latitude * ids.size) + latitude) / (ids.size + 1)
        @longitude = ((@longitude * ids.size) + longitude) / (ids.size + 1)
        @ids << id
        @first_taken_at = taken_at if taken_at && (@first_taken_at.nil? || taken_at < @first_taken_at)
        @last_taken_at = taken_at if taken_at && (@last_taken_at.nil? || taken_at > @last_taken_at)
        recompute
      end

      def count = ids.size

      # The pin's newest photo, which is also the one the list uses as its
      # thumbnail. Set by Map#pins once, in one query for every pin.
      attr_accessor :cover

      # The nearest settlement in the local gazetteer, or nil where it knows
      # nothing (Datasets::Places). Set by Map#pins for the whole set.
      attr_accessor :place

      def near_param = "#{latitude.round(4)},#{longitude.round(4)}"

      def place_name = place&.label
      def country = place&.country

      # What a row leads with: the place if we can honestly name one, else
      # when — which was the only true thing we could say before the
      # gazetteer, and still is out at sea.
      def heading = place_name || period || "Undated"

      # "Lisbon · 12 photos · Jun 2019 – Aug 2019"
      def label
        [ place_name, "#{count} #{"photo".pluralize(count)}", period ].compact.join(" · ")
      end

      def period
        return nil if first_taken_at.nil?

        first = first_taken_at.strftime("%b %Y")
        last = last_taken_at.strftime("%b %Y")
        first == last ? first : "#{first} – #{last}"
      end

      private
        def recompute
          @x = (longitude + 180.0) / 360.0 * WIDTH
          @y = (90.0 - latitude) / 180.0 * HEIGHT
        end
    end

    # `scope` is any Photo relation the caller has already narrowed (own
    # photos only — see the class comment); Map applies the located filter
    # itself so no caller can forget it.
    def initialize(scope)
      @scope = scope.located
    end

    def pins
      @pins ||= build_pins.tap do |pins|
        attach_covers(pins)
        attach_places(pins)
      end
    end

    # Pins grouped by country, busiest first — the shape the map page browses
    # by, and (once zoom exists) the unit a reader wants to zoom to. Pins the
    # gazetteer can't place group under nil rather than disappearing.
    def by_country
      pins.group_by(&:country)
        .sort_by { |country, group| [ country ? 0 : 1, -group.sum(&:count) ] }
    end

    def any? = pins.any?
    def photo_count = @photo_count ||= rows.size
    def place_count = pins.size

    # Newest first: where you've been lately is what a travel page is for.
    def recent_pins(limit = 6)
      pins.sort_by { |pin| [ pin.last_taken_at ? 0 : 1, -(pin.last_taken_at&.to_i || 0) ] }.first(limit)
    end

    def first_taken_at = pins.filter_map(&:first_taken_at).min
    def last_taken_at = pins.filter_map(&:last_taken_at).max

    # The SVG window, widened from the default crop if any pin falls
    # outside it. Returned as the viewBox string plus the aspect ratio the
    # container needs, so the map is never letterboxed or squashed.
    def view_box
      top, bottom = window
      "0 #{round(top)} #{WIDTH.to_i} #{round(bottom - top)}"
    end

    def aspect_ratio
      top, bottom = window
      (WIDTH / (bottom - top)).round(4)
    end

    # A pin's position inside the current window, as CSS percentages.
    def position(pin)
      top, bottom = window
      { left: percent(pin.x / WIDTH), top: percent((pin.y - top) / (bottom - top)) }
    end

    private
      def window
        @window ||= begin
          top = (90.0 - DEFAULT_TOP_LAT) / 180.0 * HEIGHT
          bottom = (90.0 - DEFAULT_BOTTOM_LAT) / 180.0 * HEIGHT

          pins.each do |pin|
            top = [ pin.y - WINDOW_PADDING, 0.0 ].max if pin.y < top
            bottom = [ pin.y + WINDOW_PADDING, HEIGHT ].min if pin.y > bottom
          end

          [ top, bottom ]
        end
      end

      def percent(fraction) = "#{(fraction * 100).round(4)}%"
      def round(value) = value.round(2)

      # Only the four columns clustering needs — a library with 40,000
      # located photos would be 40,000 rows either way, but not 40,000
      # instantiated models with their attachments in tow.
      def rows
        @rows ||= @scope.reorder(taken_at: :desc, id: :desc)
          .pluck(:id, :latitude, :longitude, :taken_at)
      end

      # Greedy clustering against a spatial hash: each photo joins the first
      # existing pin whose centre is within CLUSTER_RADIUS, or starts one.
      # Cells are 2×the radius and seeds are indexed by their own cell, so a
      # centroid can drift at most one cell from its seed — which is why
      # scanning the 3×3 neighbourhood is exhaustive rather than merely
      # likely.
      def build_pins
        buckets = Hash.new { |hash, key| hash[key] = [] }
        pins = []

        rows.each do |id, latitude, longitude, taken_at|
          latitude = latitude.to_f
          longitude = longitude.to_f
          x = (longitude + 180.0) / 360.0 * WIDTH
          y = (90.0 - latitude) / 180.0 * HEIGHT
          cell = [ (x / CELL).floor, (y / CELL).floor ]

          match = neighbours(buckets, cell).find do |pin|
            Math.hypot(pin.x - x, pin.y - y) <= CLUSTER_RADIUS
          end

          if match
            match.add(id, latitude, longitude, taken_at)
          else
            pin = Pin.new(id, latitude, longitude, taken_at)
            pins << pin
            buckets[cell] << pin
          end
        end

        pins
      end

      def neighbours(buckets, (column, row))
        (-1..1).flat_map { |dx| (-1..1).flat_map { |dy| buckets[[ column + dx, row + dy ]] } }
      end

      # One query for every pin's thumbnail rather than one per pin: the
      # first id in each pin is its newest photo, since rows arrive newest
      # first.
      def attach_covers(pins)
        covers = Photo.where(id: pins.map { |pin| pin.ids.first })
          .with_attached_image.index_by(&:id)
        pins.each { |pin| pin.cover = covers[pin.ids.first] }
      end

      # Names come from the shipped gazetteer, in memory, once per pin — no
      # network, no model, and an absent or unhelpful file just leaves pins
      # unnamed (Datasets::Places).
      def attach_places(pins)
        gazetteer = Datasets::Places.current
        pins.each { |pin| pin.place = gazetteer.nearest(pin.latitude, pin.longitude) }
      end
  end
end
