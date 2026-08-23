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
  # * **It never geocodes over the network, and never asks a model.** Pin
  #   names come from a gazetteer that ships in the repo (Datasets::Places),
  #   which is why a pin says "Near Cody" when that is all anyone can
  #   honestly say, and says nothing at all out at sea. A lookup service
  #   would leak the same itinerary as a tile host; a model would invent a
  #   confident "Paris", which is worse than an honest dot.
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

    # Zoomed views (a trip, a country) are built from a requested box rather
    # than the whole world. It is padded so nothing sits on the edge, never
    # narrower than MIN_SPAN — a day in one city is a box a few hundred
    # metres across, and blown up to fill a card that is a meaningless smear
    # of coastline — and kept between these aspect ratios by growing the
    # short side, never by squashing the projection.
    BOUNDS_PADDING = 0.25
    MIN_PADDING = 1.5
    MIN_SPAN = 14.0
    TARGET_ASPECT = 2.0
    MIN_ASPECT = 1.1

    # Clustering distance in map units (1 unit = 0.36°). At 6 units two pins
    # can still be told apart at the size the map renders, and cities an
    # hour apart stay separate pins — London and Paris are ~9.6 units, and
    # merging them would be a lie about where you'd been.
    CLUSTER_RADIUS = 6.0
    # The same radius in degrees, for the Photo.near box a pin links to.
    CLUSTER_DEGREES = (CLUSTER_RADIUS / HEIGHT * 180.0).round(4)

    # A cluster of photos taken in roughly one spot.
    class Pin
      attr_reader :ids, :x, :y, :latitude, :longitude, :first_taken_at, :last_taken_at

      def initialize(id, latitude, longitude, taken_at)
        @ids = [ id ]
        @latitude = latitude
        @longitude = longitude
        @days = Set.new
        @first_taken_at = @last_taken_at = taken_at
        note_time(taken_at)
        recompute
      end

      def add(id, latitude, longitude, taken_at)
        @latitude = ((@latitude * ids.size) + latitude) / (ids.size + 1)
        @longitude = ((@longitude * ids.size) + longitude) / (ids.size + 1)
        @ids << id
        note_time(taken_at)
        recompute
      end

      def count = ids.size

      # Distinct days, not photo count, is what says where someone actually
      # *lives*: one wedding can out-shoot a year of ordinary evenings.
      def day_count = @days.size

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
        def note_time(taken_at)
          return if taken_at.nil?

          @days << taken_at.to_date
          @first_taken_at = taken_at if @first_taken_at.nil? || taken_at < @first_taken_at
          @last_taken_at = taken_at if @last_taken_at.nil? || taken_at > @last_taken_at
        end

        def recompute
          @x = (longitude + 180.0) / 360.0 * WIDTH
          @y = (90.0 - latitude) / 180.0 * HEIGHT
        end
    end

    # `scope` is any Photo relation the caller has already narrowed (own
    # photos only — see the class comment); Map applies the located filter
    # itself so no caller can forget it. `bounds` zooms the view to a box
    # (a trip, a country) and narrows the scope to match, so a zoomed map
    # reads only the photos it is going to draw.
    def initialize(scope, bounds: nil)
      @bounds = bounds&.symbolize_keys
      @scope = scope.located
      @scope = @scope.within(**@bounds) if @bounds
    end

    attr_reader :bounds

    # The four columns clustering needs — a library with 40,000 located
    # photos would be 40,000 rows either way, but not 40,000 instantiated
    # models with their attachments in tow. Public because the trip detector
    # works off the same pull rather than making its own.
    def rows
      @rows ||= @scope.reorder(taken_at: :desc, id: :desc)
        .pluck(:id, :latitude, :longitude, :taken_at)
    end

    # Greedy clustering against a spatial hash: each photo joins the first
    # existing pin whose centre is within `radius`, or starts one. Cells are
    # 2x the radius and seeds are indexed by their own cell, so a centroid
    # can drift at most one cell from its seed — which is why scanning the
    # 3x3 neighbourhood is exhaustive rather than merely likely.
    #
    # A class method because a trip is the same question asked of a subset:
    # which spots did these photos happen in?
    def self.cluster(rows, radius: CLUSTER_RADIUS)
      cell_size = radius * 2
      buckets = Hash.new { |hash, key| hash[key] = [] }
      pins = []

      rows.each do |id, latitude, longitude, taken_at|
        latitude = latitude.to_f
        longitude = longitude.to_f
        x = (longitude + 180.0) / 360.0 * WIDTH
        y = (90.0 - latitude) / 180.0 * HEIGHT
        cell = [ (x / cell_size).floor, (y / cell_size).floor ]

        match = (-1..1).flat_map { |dx| (-1..1).flat_map { |dy| buckets[[ cell.first + dx, cell.second + dy ]] } }
          .find { |pin| Math.hypot(pin.x - x, pin.y - y) <= radius }

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

    def pins
      @pins ||= self.class.cluster(rows, radius: cluster_radius).tap do |pins|
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

    # The SVG window as a viewBox, plus the aspect ratio its container needs
    # so the map is never letterboxed or squashed. The world view is
    # full-width and crops the empty polar bands; a bounded view is whatever
    # was asked for, padded.
    def view_box
      window.values_at(:x, :y, :width, :height).map { |value| round(value) }.join(" ")
    end

    def aspect_ratio = (window[:width] / window[:height]).round(4)

    # Is this a zoomed view? The basemap uses it to decide how much coastline
    # detail is worth drawing.
    def zoomed? = window[:width] < WIDTH

    # A pin's position inside the current window, as CSS percentages.
    def position(pin)
      { left: percent((pin.x - window[:x]) / window[:width]),
        top: percent((pin.y - window[:y]) / window[:height]) }
    end

    # The window's own corners, for a caller that wants to hand this view to
    # someone else as a link.
    def bbox_param
      south = 90.0 - ((window[:y] + window[:height]) / HEIGHT * 180.0)
      north = 90.0 - (window[:y] / HEIGHT * 180.0)
      west = (window[:x] / WIDTH * 360.0) - 180.0
      east = ((window[:x] + window[:width]) / WIDTH * 360.0) - 180.0
      [ south, west, north, east ].map { |value| value.round(4) }.join(",")
    end

    private
      # The clustering distance is a distance *on screen*, not on Earth: at
      # world zoom two pins 6 units apart nearly touch, and zoomed into one
      # country the same 6 units would swallow it whole. Scaling by the
      # window keeps a pin the same size in the reader's eye — which is why
      # zooming in is what finally separates London from Paris.
      #
      # Only the bounded window is consulted: the default one is always
      # full-width, and asking for it here would be circular, since it grows
      # to fit the pins that clustering hasn't produced yet.
      def cluster_radius = bounds ? CLUSTER_RADIUS * (window[:width] / WIDTH) : CLUSTER_RADIUS

      def window = @window ||= bounds ? bounded_window : default_window

      # The whole world, minus the polar bands nobody's holiday snaps live
      # in — but only as a default: a pin outside the crop pushes it back
      # out rather than falling off the edge of its own map.
      def default_window
        top = (90.0 - DEFAULT_TOP_LAT) / 180.0 * HEIGHT
        bottom = (90.0 - DEFAULT_BOTTOM_LAT) / 180.0 * HEIGHT

        pins.each do |pin|
          top = [ pin.y - WINDOW_PADDING, 0.0 ].max if pin.y < top
          bottom = [ pin.y + WINDOW_PADDING, HEIGHT ].min if pin.y > bottom
        end

        { x: 0.0, y: top, width: WIDTH, height: bottom - top }
      end

      # A requested box, padded so pins never sit on the edge, grown to a
      # sane shape, and clamped to the world. It only ever grows: cropping
      # would drop a photo out of a view that claims to hold it.
      def bounded_window
        x1, y1 = project(bounds[:north], bounds[:west])
        x2, y2 = project(bounds[:south], bounds[:east])
        left, right = [ x1, x2 ].minmax
        top, bottom = [ y1, y2 ].minmax

        pad = [ (right - left) * BOUNDS_PADDING, (bottom - top) * BOUNDS_PADDING, MIN_PADDING ].max
        left -= pad
        right += pad
        top -= pad
        bottom += pad

        width, height = right - left, bottom - top
        # A day in one city is a box a few hundred metres across; blown up
        # to fill a card it would be a meaningless smear of coastline.
        if width < MIN_SPAN
          left -= (MIN_SPAN - width) / 2
          width = MIN_SPAN
        end
        if height < MIN_SPAN / TARGET_ASPECT
          top -= ((MIN_SPAN / TARGET_ASPECT) - height) / 2
          height = MIN_SPAN / TARGET_ASPECT
        end
        # Grow the short side rather than squashing: the projection is only
        # honest at its own aspect ratio.
        if width / height > TARGET_ASPECT
          grown = width / TARGET_ASPECT
          top -= (grown - height) / 2
          height = grown
        elsif width / height < MIN_ASPECT
          grown = height * MIN_ASPECT
          left -= (grown - width) / 2
          width = grown
        end

        width = [ width, WIDTH ].min
        height = [ height, HEIGHT ].min
        { x: left.clamp(0.0, WIDTH - width), y: top.clamp(0.0, HEIGHT - height),
          width: width, height: height }
      end

      def project(latitude, longitude)
        [ (longitude + 180.0) / 360.0 * WIDTH, (90.0 - latitude) / 180.0 * HEIGHT ]
      end

      def percent(fraction) = "#{(fraction * 100).round(4)}%"
      # Whole numbers stay whole: "0 22.22 1000 388.89" beats
      # "0.0 22.22 1000.0 388.89" in a viewBox a person might read.
      def round(value)
        rounded = value.round(2)
        rounded == rounded.to_i ? rounded.to_i : rounded
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
