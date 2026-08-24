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
    MIN_ASPECT = 1.5

    # Clustering distance in map units (1 unit = 0.36°). At 6 units two pins
    # can still be told apart at the size the map renders, and cities an
    # hour apart stay separate pins — London and Paris are ~9.6 units, and
    # merging them would be a lie about where you'd been.
    CLUSTER_RADIUS = 6.0
    # The same radius in degrees, for the Photo.near box a pin links to.
    CLUSTER_DEGREES = (CLUSTER_RADIUS / HEIGHT * 180.0).round(4)

    # How many settlement names a zoomed map is lettered with before it stops
    # being a map and starts being a list.
    CONTEXT_LABELS = 12

    # A cluster of photos taken in roughly one spot.
    class Pin
      attr_reader :ids, :x, :y, :latitude, :longitude, :first_at, :last_at

      # Timestamps arrive as epoch seconds and stay that way: a Time is
      # built only for the two ends of a pin that something is about to
      # print, not for every photo that went into it.
      def first_taken_at = @first_taken_at ||= (Time.zone.at(first_at) if first_at)
      def last_taken_at = @last_taken_at ||= (Time.zone.at(last_at) if last_at)

      def initialize(id, latitude, longitude, at)
        @ids = [ id ]
        @latitude = latitude
        @longitude = longitude
        @days = Set.new
        note_time(at)
        recompute
      end

      def add(id, latitude, longitude, at)
        @latitude = ((@latitude * ids.size) + latitude) / (ids.size + 1)
        @longitude = ((@longitude * ids.size) + longitude) / (ids.size + 1)
        @ids << id
        note_time(at)
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
        def note_time(at)
          return if at.nil?

          # Integer day buckets rather than Dates: this only ranks which
          # cluster is home, where a photo taken minutes after midnight on a
          # daylight-saving boundary landing in the day before changes
          # nothing. Anything user-visible converts properly (Travel::Trips).
          @days << ((at + Time.zone.utc_offset) / 86_400)
          @first_at = at if @first_at.nil? || at < @first_at
          @last_at = at if @last_at.nil? || at > @last_at
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
    #
    # The casts are the difference between a map that opens and one that
    # stalls. A plain pluck of these columns hands back a BigDecimal per
    # coordinate and a TimeWithZone per photo — on a 60,000-photo library
    # that is 750ms of object allocation before any arithmetic happens, and
    # the map wants floats and a number anyway. Asking SQLite for those
    # directly costs 120ms. (SQLite-specific, which this app is.)
    ROW_COLUMNS = [
      "photos.id",
      "CAST(photos.latitude AS REAL)",
      "CAST(photos.longitude AS REAL)",
      "CAST(strftime('%s', photos.taken_at) AS INTEGER)"
    ].map { |column| Arel.sql(column) }.freeze

    def rows
      @rows ||= @scope.reorder(taken_at: :desc, id: :desc).pluck(*ROW_COLUMNS)
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
      buckets = {}
      pins = []

      rows.each do |id, latitude, longitude, at|
        latitude = latitude.to_f
        longitude = longitude.to_f
        x = (longitude + 180.0) / 360.0 * WIDTH
        y = (90.0 - latitude) / 180.0 * HEIGHT
        column = (x / cell_size).floor
        row = (y / cell_size).floor

        match = nearest_pin(buckets, column, row, x, y, radius)

        if match
          match.add(id, latitude, longitude, at)
        else
          pin = Pin.new(id, latitude, longitude, at)
          pins << pin
          (buckets[cell_key(column, row)] ||= []) << pin
        end
      end

      pins
    end

    # Deliberately loops rather than reading prettily. This runs once per
    # photo in the library, so the nine-cell probe allocated nine arrays a
    # photo when it was a flat_map, and the hash's default block was storing
    # an empty array for every cell it merely looked at.
    def self.nearest_pin(buckets, column, row, x, y, radius)
      dx = -1
      while dx <= 1
        dy = -1
        while dy <= 1
          bucket = buckets[cell_key(column + dx, row + dy)]
          if bucket
            index = 0
            while index < bucket.size
              pin = bucket[index]
              a = pin.x - x
              b = pin.y - y
              # The cheap rejection first: most candidates fail on one axis
              # and never need the square root.
              return pin if a.abs <= radius && b.abs <= radius && Math.sqrt((a * a) + (b * b)) <= radius

              index += 1
            end
          end
          dy += 1
        end
        dx += 1
      end
      nil
    end

    # One integer instead of a two-element array, so a probe allocates
    # nothing. The map is 1000x500 units and cells are never smaller than a
    # fraction of a unit, so the row fits well inside the multiplier.
    def self.cell_key(column, row) = (column * 1_000_003) + row

    private_class_method :nearest_pin, :cell_key

    # The box that holds a set of pins, as a bbox parameter — how a country
    # row on the map page hands its own corner of the world to a zoom link.
    def self.bbox_for(pins)
      latitudes = pins.map(&:latitude)
      longitudes = pins.map(&:longitude)
      [ latitudes.min, longitudes.min, latitudes.max, longitudes.max ]
        .map { |value| value.round(4) }.join(",")
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
      left, top = fraction_of(pin.x, pin.y)
      { left: percent(left), top: percent(top) }
    end

    # The window in map units — what the basemap needs to pick the coastline
    # cells that are actually in view.
    def window_box = window.values_at(:x, :y, :width, :height)

    # Settlement names to letter a zoomed map with. A coastline with nothing
    # written on it is a shape; the same coastline with "Porto" and "Lisboa"
    # on it is a map. Drawn only when zoomed, because at world scale a dozen
    # city names is noise on top of the pins that matter.
    #
    # Labels are placed biggest-first and skipped when they'd land on one
    # already placed — the cheap version of collision avoidance, and enough
    # when there are at most a dozen.
    Label = Data.define(:name, :left, :top)

    def context_labels(gazetteer: Datasets::Places.current)
      return [] unless zoomed?

      @context_labels ||= begin
        # A pin is the point of the map; lettering is context. Where they
        # collide, the lettering gives way.
        placed = pins.map { |pin| fraction_of(pin.x, pin.y) }
        gazetteer.within(**window_bounds, limit: CONTEXT_LABELS).filter_map do |place|
          left, top = fraction_of(*project(place.latitude, place.longitude))
          next if placed.any? { |lx, ly| (lx - left).abs < 0.12 && (ly - top).abs < 0.06 }

          placed << [ left, top ]
          Label.new(name: place.name, left: percent(left), top: percent(top))
        end
      end
    end

    # The window's own corners, for a caller that wants to hand this view to
    # someone else as a link.
    def bbox_param = window_bounds.values_at(:south, :west, :north, :east).map { |value| value.round(4) }.join(",")

    # The window as latitudes and longitudes rather than map units.
    def window_bounds
      { south: 90.0 - ((window[:y] + window[:height]) / HEIGHT * 180.0),
        north: 90.0 - (window[:y] / HEIGHT * 180.0),
        west: (window[:x] / WIDTH * 360.0) - 180.0,
        east: ((window[:x] + window[:width]) / WIDTH * 360.0) - 180.0 }
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

      # Where a point in map units sits inside the window, 0..1.
      def fraction_of(x, y)
        [ (x - window[:x]) / window[:width], (y - window[:y]) / window[:height] ]
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
