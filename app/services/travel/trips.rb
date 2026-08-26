module Travel
  # Finds the trips already sitting in a photo library (docs/TRAVEL.md §3).
  #
  # A trip is one of the few things a life assistant can work out on its own
  # without guessing: photos carry where and when, and "away from home for
  # more than a day" is a fact, not an inference. So this asks nothing of the
  # user and calls no model — it proposes, and the user saves the ones that
  # were really trips and names them.
  #
  # Home is the cluster with the most distinct *days*, not the most photos:
  # one wedding can out-shoot a year of ordinary evenings, and the place you
  # keep coming back to is the place you live.
  class Trips
    # Far enough that you went somewhere. Deliberately generous — a day out
    # two towns over is not a trip, and calling it one would bury the real
    # ones.
    AWAY_KM = 100.0
    # Days without a photo that still count as the same trip. Three covers
    # the stretch in the middle where nobody photographed anything.
    GAP_DAYS = 3
    # Below these it is an errand or a stray timestamp, not a trip.
    MIN_PHOTOS = 3
    MIN_DAYS = 2

    EARTH_RADIUS_KM = 6371.0
    KM_PER_DEGREE = 111.32
    # Beyond this in either direction you are certainly away; inside this in
    # both you are certainly not. Only the band between needs real
    # trigonometry.
    AWAY_DEGREES = AWAY_KM / KM_PER_DEGREE
    CERTAINLY_NEAR = AWAY_KM / KM_PER_DEGREE / Math.sqrt(2)

    # A proposal, not a record: everything here is recomputed from the
    # photos each time, and only becomes a row when the user says so.
    Candidate = Data.define(:starts_on, :ends_on, :photo_count, :day_count,
      :bounds, :suggested_name, :place_label, :cover_id, :latitude, :longitude) do
      def days = (ends_on - starts_on).to_i + 1
      def period
        same_month = starts_on.strftime("%b %Y") == ends_on.strftime("%b %Y")
        same_month ? "#{starts_on.strftime("%-d")}–#{ends_on.strftime("%-d %b %Y")}" :
          "#{starts_on.strftime("%-d %b")} – #{ends_on.strftime("%-d %b %Y")}"
      end
    end

    # Takes the map the page has already built, so the library is plucked
    # once for both.
    def initialize(map, gazetteer: Datasets::Places.current)
      @map = map
      @gazetteer = gazetteer
    end

    def home = @home ||= @map.pins.max_by { |pin| [ pin.day_count, pin.count ] }

    def candidates
      @candidates ||= home ? runs.filter_map { |rows| candidate_for(rows) } : []
    end

    # The candidates overlapping a date range — what places a planned trip
    # once its dates have photos (D-trip-spine): the same detection, keyed
    # to the trip's own dates instead of offered as something new.
    def covering(starts_on, ends_on)
      candidates.select { |candidate| candidate.starts_on <= ends_on && candidate.ends_on >= starts_on }
    end

    private
      # Photos far enough from home to be somewhere else, grouped into runs
      # of days no more than GAP_DAYS apart.
      #
      # Grouping is by integer day bucket rather than by Date, because
      # building a Date per photo is most of the cost of this pass on a big
      # library. The dates a candidate actually reports are converted from
      # real timestamps (see #candidate_for), so the only thing riding on
      # the arithmetic is which side of a daylight-saving midnight a photo
      # groups on — and runs join across three blank days anyway.
      def runs
        offset = Time.zone.utc_offset
        away = @map.rows.select { |_id, latitude, longitude, at| at && away?(latitude.to_f, longitude.to_f) }
        return [] if away.empty?

        by_day = away.group_by { |_id, _lat, _lon, at| (at + offset) / 86_400 }
        # The gap is *blank* days, so consecutive photo days are 1 apart and
        # have no gap at all.
        by_day.keys.sort.slice_when { |before, after| after - before - 1 > GAP_DAYS }
          .map { |days| days.flat_map { |day| by_day[day] } }
      end

      def candidate_for(rows)
        times = rows.map(&:fourth)
        starts_on = Time.zone.at(times.min).to_date
        ends_on = Time.zone.at(times.max).to_date
        days = (ends_on - starts_on).to_i + 1
        return nil if rows.size < MIN_PHOTOS || days < MIN_DAYS

        # The same clustering the map uses, over just this trip's photos:
        # where within the trip did things actually happen?
        pins = Photos::Map.cluster(rows).sort_by { |pin| -pin.count }
        places = pins.filter_map { |pin| @gazetteer.nearest(pin.latitude, pin.longitude) }
        latitudes = rows.map { |_id, latitude, *| latitude.to_f }
        longitudes = rows.map { |_id, _lat, longitude, *| longitude.to_f }

        Candidate.new(
          starts_on: starts_on, ends_on: ends_on,
          photo_count: rows.size, day_count: day_count_for(rows),
          bounds: { south: latitudes.min, north: latitudes.max,
                    west: longitudes.min, east: longitudes.max },
          suggested_name: name_for(places, starts_on),
          place_label: places.first&.qualified,
          # Rows arrive newest first, so the run's first row is its newest
          # photo — the one that makes the best cover.
          cover_id: rows.first.first,
          latitude: pins.first.latitude, longitude: pins.first.longitude
        )
      end

      # Distinct days with a photo — how much of the trip is actually
      # recorded, as opposed to how long it ran.
      def day_count_for(rows)
        offset = Time.zone.utc_offset
        rows.map { |_id, _lat, _lon, at| (at + offset) / 86_400 }.uniq.size
      end

      # What to call it before the user does. One place is that place; a
      # handful in one country is the country ("Portugal" beats "Lisbon and
      # Porto and Faro"); anything else is the two biggest, joined. A trip
      # somewhere the gazetteer has never heard of gets its month, which is
      # at least true.
      def name_for(places, starts_on)
        named = places.reject { |place| place.near? }.presence || places
        return "Trip, #{starts_on.strftime("%b %Y")}" if named.empty?

        countries = named.filter_map { |place| place.country.presence }.uniq
        return countries.first if named.many? && countries.one?

        named.first(2).map(&:name).uniq.to_sentence(two_words_connector: " and ",
          last_word_connector: " and ")
      end

      # Most photos are obviously home or obviously abroad, and a degree of
      # latitude is 111km wherever you stand — so a subtraction settles it
      # for nearly all of them, and only the handful in the band around the
      # threshold pay for a haversine. This runs once per photo in the
      # library.
      def away?(latitude, longitude)
        d_lat = (latitude - home.latitude).abs
        return true if d_lat > AWAY_DEGREES

        d_lon = (longitude - home.longitude).abs
        d_lon = 360 - d_lon if d_lon > 180
        # A degree of longitude shrinks towards the poles, so the certainly-
        # far test has to widen with it.
        return true if d_lon > away_longitude_degrees
        return false if d_lat < CERTAINLY_NEAR && d_lon < CERTAINLY_NEAR

        distance(latitude, longitude, home.latitude, home.longitude) > AWAY_KM
      end

      def away_longitude_degrees
        @away_longitude_degrees ||=
          AWAY_DEGREES / Math.cos(radians(home.latitude)).abs.clamp(0.01, 1.0)
      end

      def distance(lat1, lon1, lat2, lon2)
        d_lat = radians(lat2 - lat1)
        d_lon = radians(lon2 - lon1)
        a = (Math.sin(d_lat / 2)**2) +
          (Math.cos(radians(lat1)) * Math.cos(radians(lat2)) * (Math.sin(d_lon / 2)**2))
        2 * EARTH_RADIUS_KM * Math.asin(Math.sqrt(a).clamp(0.0, 1.0))
      end

      def radians(degrees) = degrees * Math::PI / 180.0
  end
end
