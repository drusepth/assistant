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

    private
      # Photos far enough from home to be somewhere else, grouped into runs
      # of days no more than GAP_DAYS apart.
      def runs
        away = @map.rows.select do |_id, latitude, longitude, taken_at|
          taken_at && distance(latitude.to_f, longitude.to_f, home.latitude, home.longitude) > AWAY_KM
        end
        return [] if away.empty?

        by_day = away.group_by { |_id, _lat, _lon, taken_at| taken_at.to_date }
        # The gap is *blank* days, so consecutive photo days are 1 apart and
        # have no gap at all.
        by_day.keys.sort.slice_when { |before, after| (after - before).to_i - 1 > GAP_DAYS }
          .map { |days| days.flat_map { |day| by_day[day] } }
      end

      def candidate_for(rows)
        days = rows.map { |_id, _lat, _lon, taken_at| taken_at.to_date }.uniq.sort
        starts_on, ends_on = days.first, days.last
        return nil if rows.size < MIN_PHOTOS || (ends_on - starts_on).to_i + 1 < MIN_DAYS

        # The same clustering the map uses, over just this trip's photos:
        # where within the trip did things actually happen?
        pins = Photos::Map.cluster(rows).sort_by { |pin| -pin.count }
        places = pins.filter_map { |pin| @gazetteer.nearest(pin.latitude, pin.longitude) }
        latitudes = rows.map { |_id, latitude, *| latitude.to_f }
        longitudes = rows.map { |_id, _lat, longitude, *| longitude.to_f }

        Candidate.new(
          starts_on: starts_on, ends_on: ends_on,
          photo_count: rows.size, day_count: days.size,
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
